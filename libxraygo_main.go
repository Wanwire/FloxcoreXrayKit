package libxraygo

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	xraycoreapplog "github.com/xtls/xray-core/app/log"
	xraycoreappstats "github.com/xtls/xray-core/app/stats"
	xraycorecommonlog "github.com/xtls/xray-core/common/log"
	xraycorefilesystem "github.com/xtls/xray-core/common/platform/filesystem"
	"github.com/xtls/xray-core/core"
	xraycore "github.com/xtls/xray-core/core"
	xraycorestats "github.com/xtls/xray-core/features/stats"
	xraycoreserial "github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
	mobasset "golang.org/x/mobile/asset"
)

// Constants for environment variable keys.
const (
	envLocationAsset = "xray.location.asset"
	envTunFd = "xray.tun.fd"
)

type XrayCoreCallbackHandler interface {
	OnStart() int
	OnStartFailure(string) int
	OnStop() int
	OnEmitStatus(int, string) int
}

type XrayCoreController struct {
	CallbackHandler XrayCoreCallbackHandler
	statsManager    xraycorestats.Manager
	coreMutex       sync.Mutex
	coreInstance    *core.Instance
	IsRunning       bool
}

func setEnv(key, value string) {
	if err := os.Setenv(key, value); err != nil {
		log.Printf("Failed to set environment variable %s: %v.", key, err)
	}
}

// consoleLogWriter logs without timestamps
type consoleLogWriter struct {
	logger *log.Logger
}

// Log writer implementation
func (w *consoleLogWriter) Write(s string) error {
	w.logger.Print(s)
	return nil
}

func (w *consoleLogWriter) Close() error {
	return nil
}

func createStdoutLogWriter() xraycorecommonlog.WriterCreator {
	return func() xraycorecommonlog.Writer {
		return &consoleLogWriter{
			logger: log.New(os.Stdout, "", 0),
		}
	}
}

func NewXrayCoreController(s XrayCoreCallbackHandler) *XrayCoreController {
	// Register custom logger
	if err := xraycoreapplog.RegisterHandlerCreator(
		xraycoreapplog.LogType_Console,
		func(lt xraycoreapplog.LogType, options xraycoreapplog.HandlerCreatorOptions) (xraycorecommonlog.Handler, error) {
			return xraycorecommonlog.NewLogger(createStdoutLogWriter()), nil
		},
	); err != nil {
		log.Printf("Failed to register log handler: %v", err)
	}

	return &XrayCoreController{
		CallbackHandler: s,
	}
}

func InitXrayCoreAssetEnv(assetPath string) {
	// Setup file reader to checks assets when file is not in the filesystem.
	xraycorefilesystem.NewFileReader = func(path string) (io.ReadCloser, error) {
		if _, err := os.Stat(path); os.IsNotExist(err) {
			_, file := filepath.Split(path)
			return mobasset.Open(file)
		}
		return os.Open(path)
	}

	// Set the environment variable for asset location.
	setEnv(envLocationAsset, assetPath)
}

func InitXrayCoreTunFdEnv(tunFd int32) {
	// Set TUN fd; set to 0 to disable TUN
	setEnv(envTunFd, strconv.Itoa(int(tunFd)))
}

func (controller *XrayCoreController) Start(configContent string) {
	controller.coreMutex.Lock()
	defer controller.coreMutex.Unlock()

	if controller.IsRunning {
		fmt.Println("XrayCoreController.Start: already running")
		return // Already running.
	}

	controller.doStart(configContent)
}

func (controller *XrayCoreController) doStart(configContent string) error {
	log.Println("Starting xray-core...")

	config, err := xraycoreserial.LoadJSONConfig(strings.NewReader(configContent))
	if err != nil {
		errorString := fmt.Sprintf("config error: %s", err)
		controller.CallbackHandler.OnStartFailure(errorString)
		return fmt.Errorf("config error: %w", err)
	}

	controller.coreInstance, err = xraycore.New(config)
	if err != nil {
		errorString := fmt.Sprintf("xray-core start failed: %s", err)
		controller.CallbackHandler.OnStartFailure(errorString)
		return fmt.Errorf("core init failed: %w", err)
	}
	controller.statsManager = controller.coreInstance.GetFeature(xraycorestats.ManagerType()).(xraycorestats.Manager)

	controller.IsRunning = true
	if err := controller.coreInstance.Start(); err != nil {
		controller.IsRunning = false
		errorString := fmt.Sprintf("xray-core start failed: %s", err)
		fmt.Printf("xray-core failed to start: %s\n", errorString)
		controller.CallbackHandler.OnStartFailure(errorString)
		return fmt.Errorf("%s", errorString)
	}

	controller.CallbackHandler.OnStart()
	controller.CallbackHandler.OnEmitStatus(1, "xray-core started")

	log.Println("Started xray-core successfully")
	return nil
}

func (controller *XrayCoreController) Stop() {
	controller.coreMutex.Lock()
	defer controller.coreMutex.Unlock()

	if !controller.IsRunning {
		fmt.Println("XrayCoreController.Stop: not running")
		return // Not running.
	}

	controller.doStop()
}

func (controller *XrayCoreController) doStop() error {
	log.Printf("stopping xray-core")

	controller.IsRunning = false
	controller.statsManager = nil

	if controller.coreInstance != nil {
		if err := controller.coreInstance.Close(); err != nil {
			log.Printf("xray-core stop error: %v", err)
		}
		controller.CallbackHandler.OnStop()
		controller.CallbackHandler.OnEmitStatus(0, "xray-core stopped")
		controller.coreInstance = nil
	}

	return nil
}

// QueryOutboundTraffic returns the number of bytes transferred over every
// outbound connection since the core was started, serialized into a single
// string so it can cross the gomobile binding boundary.
//
// The result is a sequence of ";"-terminated records, two per outbound tag:
//
//	<tag>,up,<uplinkBytes>;<tag>,down,<downlinkBytes>;
//
// Counters are read without being reset, so the values are cumulative. An empty
// string is returned when the core is not running or no outbound traffic has
// been recorded.
func (controller *XrayCoreController) QueryOutboundTraffic() string {
	controller.coreMutex.Lock()
	statsManager := controller.statsManager
	controller.coreMutex.Unlock()

	// VisitCounters is only exposed by the concrete stats manager, not the
	// features/stats.Manager interface, so we type-assert to reach it. The
	// assertion also fails when the core is stopped and the manager is nil.
	manager, ok := statsManager.(*xraycoreappstats.Manager)
	if !ok {
		return ""
	}

	// Collect both directions per outbound tag. Traffic counters are named
	// "outbound>>>[tag]>>>traffic>>>[uplink|downlink]". The tags slice preserves
	// the order in which tags are first seen so output is stable within a call.
	type traffic struct{ up, down int64 }
	byTag := make(map[string]*traffic)
	var tags []string
	manager.VisitCounters(func(name string, counter xraycorestats.Counter) bool {
		parts := strings.Split(name, ">>>")
		if len(parts) != 4 || parts[0] != "outbound" || parts[2] != "traffic" {
			return true
		}
		tag := parts[1]
		t := byTag[tag]
		if t == nil {
			t = &traffic{}
			byTag[tag] = t
			tags = append(tags, tag)
		}
		switch parts[3] {
		case "uplink":
			t.up = counter.Value()
		case "downlink":
			t.down = counter.Value()
		}
		return true
	})

	var b strings.Builder
	for _, tag := range tags {
		t := byTag[tag]
		b.WriteString(tag)
		b.WriteString(",up,")
		b.WriteString(strconv.FormatInt(t.up, 10))
		b.WriteByte(';')
		b.WriteString(tag)
		b.WriteString(",down,")
		b.WriteString(strconv.FormatInt(t.down, 10))
		b.WriteByte(';')
	}
	return b.String()
}

func XrayCoreVersion() string {
	return fmt.Sprintf("Xray-Core %s", xraycore.Version())
}
