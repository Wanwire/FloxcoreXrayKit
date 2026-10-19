package libxraygo

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type fakeCallbackHandler struct{ startFailure string }

func (h *fakeCallbackHandler) OnStart() int                 { return 0 }
func (h *fakeCallbackHandler) OnStartFailure(s string) int  { h.startFailure = s; return 0 }
func (h *fakeCallbackHandler) OnStop() int                  { return 0 }
func (h *fakeCallbackHandler) OnEmitStatus(int, string) int { return 0 }

func TestRefreshConnectionsChecksTheObservatory(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	// The connectivity check succeeds, so the failure of the blackhole counts
	config := fmt.Sprintf(`{
		"log": {"loglevel": "none"},
		"outbounds": [
			{"tag": "proxy-working", "protocol": "freedom"},
			{"tag": "proxy-broken", "protocol": "blackhole"}
		],
		"burstObservatory": {
			"subjectSelector": ["proxy"],
			"pingConfig": {
				"destination": "%[1]s/ping",
				"connectivity": "%[1]s/connectivity",
				"interval": "1h",
				"timeout": "2s",
				"sampling": 1
			}
		}
	}`, server.URL)

	handler := &fakeCallbackHandler{}
	controller := NewXrayCoreController(handler)
	controller.Start(config)
	if !controller.IsRunning {
		t.Fatalf("xray-core did not start: %s", handler.startFailure)
	}
	defer controller.Stop()

	description := controller.RefreshConnections()
	t.Log(description)
	if !strings.Contains(description, "checked 2 outbounds") ||
		!strings.Contains(description, "proxy-broken failed") ||
		strings.Contains(description, "proxy-working failed") {
		t.Fatalf("unexpected description: %s", description)
	}
}
