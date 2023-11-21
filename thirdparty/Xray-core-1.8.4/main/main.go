package main

import (
        "C"
	"flag"
	"os"
        "strings"
        "unsafe"

	"github.com/xtls/xray-core/main/commands/base"
	_ "github.com/xtls/xray-core/main/distro/all"
)

var signalledExit bool

func main() {
}

//export libxray_main
func libxray_main(argc C.int, argv **C.char, envc C.int, envv **C.char) int {
	signalledExit = false
        argc_length := int(argc)
        argv_slice := (*[1 << 30]*C.char)(unsafe.Pointer(argv))[:argc_length:argc_length]
        args := make([]string, argc_length)
        for i, s := range argv_slice {
                args[i] = C.GoString(s)
        }

        // set xray environment vars such as "xray.location.asset=/path/to/dir/holding/geosite.dat"
        envc_length := int(envc)
        envv_slice := (*[1 << 30]*C.char)(unsafe.Pointer(envv))[:envc_length:envc_length]
        for _, s := range envv_slice {
                keyval := strings.Split(C.GoString(s), "=")
                if len(keyval) == 2 {
                        os.Setenv(keyval[0], keyval[1])
                }
        }

        os.Args = args
        os.Args = getArgsV4Compatible()

	base.RootCommand.Long = "Xray is a platform for building proxies."
	base.RootCommand.Commands = append(
		[]*base.Command{
			cmdRun,
			cmdVersion,
		},
		base.RootCommand.Commands...,
	)
	base.Execute()
	if signalledExit {
		return 0
	}
	return 1
}

func getArgsV4Compatible() []string {
	if len(os.Args) == 1 {
		return []string{os.Args[0], "run"}
	}
	if os.Args[1][0] != '-' {
		return os.Args
	}
	version := false
	fs := flag.NewFlagSet("", flag.ContinueOnError)
	fs.BoolVar(&version, "version", false, "")
	// parse silently, no usage, no error output
	fs.Usage = func() {}
	fs.SetOutput(&null{})
	err := fs.Parse(os.Args[1:])
	if err == flag.ErrHelp {
		// fmt.Println("DEPRECATED: -h, WILL BE REMOVED IN V5.")
		// fmt.Println("PLEASE USE: xray help")
		// fmt.Println()
		return []string{os.Args[0], "help"}
	}
	if version {
		// fmt.Println("DEPRECATED: -version, WILL BE REMOVED IN V5.")
		// fmt.Println("PLEASE USE: xray version")
		// fmt.Println()
		return []string{os.Args[0], "version"}
	}
	// fmt.Println("COMPATIBLE MODE, DEPRECATED.")
	// fmt.Println("PLEASE USE: xray run [arguments] INSTEAD.")
	// fmt.Println()
	return append([]string{os.Args[0], "run"}, os.Args[1:]...)
}

type null struct{}

func (n *null) Write(p []byte) (int, error) {
	return len(p), nil
}
