package libxraygo

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"

	xraycoreapplog "github.com/xtls/xray-core/app/log"
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

func InitXrayCoreEnv(assetPath string) {
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
		return fmt.Errorf("config error: %w", err)
	}

	controller.coreInstance, err = xraycore.New(config)
	if err != nil {
		return fmt.Errorf("core init failed: %w", err)
	}
	controller.statsManager = controller.coreInstance.GetFeature(xraycorestats.ManagerType()).(xraycorestats.Manager)

	log.Printf("starting xray-core")
	controller.IsRunning = true
	if err := controller.coreInstance.Start(); err != nil {
		controller.IsRunning = false
		errorString := fmt.Sprintf("xray-core start failed: %v", err)
		controller.CallbackHandler.OnStartFailure(errorString)

		return fmt.Errorf(errorString)
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

func XrayCoreVersion() string {
	return fmt.Sprintf("Xray-Core %s", xraycore.Version())
}
