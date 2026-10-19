package libxraygo

import (
	"context"
	"fmt"
	"sort"
	"strings"

	xraycoreobservatory "github.com/xtls/xray-core/app/observatory"
	xraycoreextension "github.com/xtls/xray-core/features/extension"
	xraycoresplithttp "github.com/xtls/xray-core/transport/internet/splithttp"
)

// The burst observatory, with the method that patches/xray-core adds
type subjectChecker interface {
	xraycoreextension.Observatory
	CheckSubjects() ([]string, error)
}

// RefreshConnections forgets the pooled XHTTP connections and checks the
// outbounds of the burst observatory. Call it when the connections and the
// results of the observatory may be stale, such as after the device slept:
// the balancers then stop using an outbound whose connection broke during
// the sleep. It returns when the check has finished, after at most the
// timeout of the check, with a description of what it did and of the
// outbounds after the check.
func (controller *XrayCoreController) RefreshConnections() string {
	controller.coreMutex.Lock()
	instance := controller.coreInstance
	running := controller.IsRunning
	controller.coreMutex.Unlock()
	if !running || instance == nil {
		return "xray-core is not running"
	}

	var b strings.Builder
	fmt.Fprintf(&b, "forgot %d XHTTP connections", xraycoresplithttp.ForgetConnections())

	observatory, ok := instance.GetFeature(xraycoreextension.ObservatoryType()).(subjectChecker)
	if !ok {
		b.WriteString("; no burst observatory to check")
		return b.String()
	}
	tags, err := observatory.CheckSubjects()
	if err != nil {
		fmt.Fprintf(&b, "; check failed: %v", err)
		return b.String()
	}
	fmt.Fprintf(&b, "; checked %d outbounds", len(tags))

	message, err := observatory.GetObservation(context.Background())
	if result, ok := message.(*xraycoreobservatory.ObservationResult); err == nil && ok {
		statuses := result.GetStatus()
		sort.Slice(statuses, func(i, j int) bool { return statuses[i].OutboundTag < statuses[j].OutboundTag })
		for i, status := range statuses {
			if i == 0 {
				b.WriteString(":")
			}
			if status.Alive {
				fmt.Fprintf(&b, " %s %dms", status.OutboundTag, status.Delay)
			} else {
				fmt.Fprintf(&b, " %s failed", status.OutboundTag)
			}
		}
	}
	return b.String()
}
