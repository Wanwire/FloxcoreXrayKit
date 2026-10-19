package libxraygo

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"sync/atomic"
	"testing"
	"time"

	xraycoreliveness "github.com/xtls/xray-core/app/observatory/liveness"
)

// The "demote" of a balancer turns the liveness tracking on, and the next
// start turns it off again for a configuration without one: the tracking is
// global, and xray-core restarts within the app's process.
func TestStartResetsLiveness(t *testing.T) {
	t.Cleanup(xraycoreliveness.Reset)
	for _, c := range []struct {
		settings string
		want     bool
	}{
		{`{"demote": {"failures": 3, "window": "20s", "replyTimeout": "5s", "minReplyBytes": 1}}`, true},
		{`{}`, false},
	} {
		handler := &fakeCallbackHandler{}
		controller := NewXrayCoreController(handler)
		controller.Start(`{
			"log": {"loglevel": "none"},
			"outbounds": [{"tag": "proxy-a", "protocol": "freedom"}],
			"burstObservatory": {"subjectSelector": ["proxy-"],
				"pingConfig": {"destination": "http://192.0.2.1/", "interval": "1h"}},
			"routing": {"balancers": [{"tag": "b", "selector": ["proxy-"],
				"strategy": {"type": "leastLoad", "settings": ` + c.settings + `}}]}
		}`)
		if !controller.IsRunning {
			t.Fatalf("%s: xray-core did not start: %s", c.settings, handler.startFailure)
		}
		got := xraycoreliveness.Enabled()
		controller.Stop()
		if got != c.want {
			t.Errorf("%s: liveness tracking on: %v, want %v", c.settings, got, c.want)
		}
	}
}

// relay forwards each connection to its server, or, while it blackholes,
// takes what the connection sends and never answers, as a blocked server
// does.
type relay struct {
	listener  net.Listener
	server    string
	blackhole atomic.Bool
}

func newRelay(t *testing.T, server string) *relay {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	r := &relay{listener: listener, server: server}
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go r.handle(conn)
		}
	}()
	return r
}

func (r *relay) handle(conn net.Conn) {
	defer conn.Close()
	if r.blackhole.Load() {
		io.Copy(io.Discard, conn)
		return
	}
	upstream, err := net.Dial("tcp", r.server)
	if err != nil {
		return
	}
	defer upstream.Close()
	go func() {
		io.Copy(upstream, conn)
		upstream.(*net.TCPConn).CloseWrite()
	}()
	io.Copy(conn, upstream)
}

// newServer starts a web server that answers every request with its name,
// so that the answer tells which outbound carried the request.
func newServer(t *testing.T, name string) string {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, name)
	}))
	t.Cleanup(server.Close)
	return server.Listener.Addr().String()
}

// startBalancer starts xray-core with a socks inbound whose connections go
// to a leastLoad balancer over proxy-a and proxy-b, which reach their
// servers through the relays a and b. The balancer favours proxy-a while it
// qualifies. It returns a function that makes one request through the socks
// inbound, on a new connection, and returns the answer, or "" when the
// request failed.
func startBalancer(t *testing.T, a, b *relay, demote string) (*XrayCoreController, func() string) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	socksPort := listener.Addr().(*net.TCPAddr).Port
	listener.Close()

	handler := &fakeCallbackHandler{}
	controller := NewXrayCoreController(handler)
	controller.Start(fmt.Sprintf(`{
		"log": {"loglevel": "none"},
		"inbounds": [{"tag": "socks", "listen": "127.0.0.1", "port": %d, "protocol": "socks",
			"settings": {"auth": "noauth"}}],
		"outbounds": [
			{"tag": "proxy-a", "protocol": "freedom", "settings": {"redirect": "%s"}},
			{"tag": "proxy-b", "protocol": "freedom", "settings": {"redirect": "%s"}}
		],
		"burstObservatory": {"subjectSelector": ["proxy-"], "pingConfig": {
			"destination": "http://192.0.2.1/ping", "interval": "24h", "timeout": "2s", "sampling": 1}},
		"routing": {
			"rules": [{"type": "field", "inboundTag": ["socks"], "balancerTag": "lb"}],
			"balancers": [{"tag": "lb", "selector": ["proxy-"], "strategy": {"type": "leastLoad",
				"settings": {"costs": [{"regexp": false, "match": "proxy-a", "value": 0.000001}],
				"demote": %s}}}]
		}
	}`, socksPort, a.listener.Addr(), b.listener.Addr(), demote))
	if !controller.IsRunning {
		t.Fatalf("xray-core did not start: %s", handler.startFailure)
	}
	t.Cleanup(controller.Stop)
	// The balancer picks among the outbounds with a health check result
	t.Log(controller.RefreshConnections())

	client := &http.Client{
		Transport: &http.Transport{
			Proxy:             http.ProxyURL(&url.URL{Scheme: "socks5", Host: fmt.Sprintf("127.0.0.1:%d", socksPort)}),
			DisableKeepAlives: true,
		},
		Timeout: time.Second,
	}
	get := func() string {
		response, err := client.Get("http://192.0.2.1/")
		if err != nil {
			return ""
		}
		defer response.Body.Close()
		body, err := io.ReadAll(response.Body)
		if err != nil {
			return ""
		}
		return string(body)
	}
	return controller, get
}

// An outbound whose last connections got no reply is passed over before its
// next health check, and that check's result ends it.
func TestDemoteUntilTheNextHealthCheck(t *testing.T) {
	t.Cleanup(xraycoreliveness.Reset)
	a := newRelay(t, newServer(t, "a"))
	b := newRelay(t, newServer(t, "b"))
	controller, get := startBalancer(t, a, b,
		`{"failures": 3, "window": "20s", "replyTimeout": "300ms", "minReplyBytes": 1}`)

	for i := 0; i < 3; i++ {
		if got := get(); got != "a" {
			t.Fatalf("request %d: answer %q, want a, the favoured outbound", i, got)
		}
	}

	a.blackhole.Store(true)
	for i := 0; i < 3; i++ {
		if got := get(); got != "" {
			t.Fatalf("request %d while a is blackholed: answer %q, want a failure through a", i, got)
		}
	}
	for i := 0; i < 3; i++ {
		if got := get(); got != "b" {
			t.Fatalf("request %d after 3 failures through a: answer %q, want b", i, got)
		}
	}

	// The demotion lasts until the next health check result, also when a
	// answers again before
	a.blackhole.Store(false)
	if got := get(); got != "b" {
		t.Fatalf("a answers again, before its health check: answer %q, want b", got)
	}
	t.Log(controller.RefreshConnections())
	if got := get(); got != "a" {
		t.Fatalf("after a's health check: answer %q, want a", got)
	}
}

// With "failures": 0 the balancer keeps an outbound whose connections get no
// replies until its health check fails.
func TestNoDemoteWithoutFailures(t *testing.T) {
	t.Cleanup(xraycoreliveness.Reset)
	a := newRelay(t, newServer(t, "a"))
	b := newRelay(t, newServer(t, "b"))
	_, get := startBalancer(t, a, b, `{"failures": 0}`)

	a.blackhole.Store(true)
	for i := 0; i < 5; i++ {
		if got := get(); got != "" {
			t.Fatalf("request %d while a is blackholed: answer %q, want a failure through a", i, got)
		}
	}
}
