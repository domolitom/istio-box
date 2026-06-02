# Deep-learning resources

Curated reading + tooling list for going **all the way down** the Istio stack, from the control plane to Linux kernel threads. Each layer has a canonical book or doc and the commands you should actually be running while reading.

## Mental model

Istio is two things glued together: **a control plane** (istiod) that compiles Kubernetes resources + Istio CRDs into a stream of Envoy configuration, and **data-plane proxies** (Envoy at sidecars / gateways / waypoints, ztunnel in ambient) that receive that config over **xDS** and act on it. The control plane is mostly a Go program (istiod) that watches the K8s API and serves a gRPC stream. Everything else is glue and traffic redirection.

Once that's solid, the rest unpacks: pilot-agent is the small Go binary that bootstraps Envoy in each proxy pod and serves the local config endpoint; xDS is the gRPC API that streams Listener/Route/Cluster/Endpoint resources; iptables (sidecar mode) or socket-redirect via istio-cni (ambient mode) is the kernel magic that pulls pod traffic into the proxy.

## Top resources — do these first

- **Istio architecture docs** — https://istio.io/latest/docs/ops/deployment/architecture/ — the canonical diagram, the source of truth.
- **Istio source code**, entry point `pilot/cmd/pilot-discovery` → `pilot/pkg/xds` — https://github.com/istio/istio . Focus on a single resource flow end-to-end (e.g., what happens when you create a Service).
- **Envoy xDS protocol reference** — https://www.envoyproxy.io/docs/envoy/latest/api-docs/xds_protocol — the wire protocol, ADS vs SOTW vs Delta, ACK/NACK, version tracking.
- **"Istio in Action"** (Manning, Posta & Maloku, 2022). The best end-to-end deep dive in print. Chapters on Envoy internals, xDS, and troubleshooting are gold.

## Layer 1 — Istio control plane (Go)

- **Source**: `istio/istio` repo, `pilot/cmd/pilot-discovery` → `pilot/pkg/xds`.
- **What to grok**: istiod is a Go program with goroutines per xDS stream, a watch loop over Kubernetes informer caches, and config translators that build Envoy snapshots.
- **The xDS server**: `pilot/pkg/xds/ads.go`, `pilot/pkg/xds/discovery.go`.
- **Config conversion**: `pilot/pkg/networking/core/v1alpha3/` — Kubernetes + Istio CRDs become Envoy config.
- **Webhook-based sidecar injection**: `pilot/pkg/bootstrap/webhook.go`.
- **Go runtime resources**:
  - **"Concurrency in Go"** by Katherine Cox-Buday (O'Reilly).
  - Ardan Labs / Bill Kennedy's series on the **M:N scheduler** (P/M/G) — https://www.ardanlabs.com/blog/2018/08/scheduling-in-go-part1.html
  - Source: `src/runtime/proc.go` in golang/go.
- **Tools**: `GODEBUG=schedtrace=1000` on istiod; `go tool pprof`; pprof endpoint on istiod port 15014.

## Layer 2 — Envoy data plane (C++)

- **Source**: `envoyproxy/envoy` — read `source/server/server.cc`, `source/server/worker_impl.cc`, `source/common/network/connection_impl.cc`.
- **Threading model**: 1 main thread (config, xDS, admin) + N worker threads (listener accept + processing). Each worker pinned to one CPU. Listeners duplicated per worker; the kernel's `SO_REUSEPORT` does load balancing. Config updates use a non-blocking "thread-local storage" pattern with a manual RCU.
- **Best reading**: Matt Klein's blog posts on Envoy threading and architecture (search "Envoy threading model").
- **C++ concurrency book if needed**: **"C++ Concurrency in Action"** by Anthony Williams.
- **Tools**:
  - `localhost:15000/config_dump`
  - `localhost:15000/clusters`
  - `localhost:15000/stats`
  - Inside the container: `top -H -p <envoy-pid>` to see threads, `cat /proc/<pid>/status` for the thread group.

## Layer 3 — ztunnel data plane (Rust)

- **Source**: `istio/ztunnel` (Rust, async/Tokio) — https://github.com/istio/ztunnel . Much smaller than Envoy — readable end-to-end in a weekend.
- **Threading model**: Tokio's work-stealing scheduler. N worker threads (default = num CPUs); futures hop between them. Connections are `tokio::spawn`-ed tasks.
- **Books**:
  - **"Rust for Rustaceans"** (Jon Gjengset) — chapters on async.
  - **"Async Programming in Rust"** (Carl Fredrik Samson).
- **Online**: Tokio tutorial https://tokio.rs/tokio/tutorial ; Async Book https://rust-lang.github.io/async-book/.
- **Tools**: `tokio-console` for live runtime introspection (requires the console subscriber feature in a custom ztunnel build).

## Layer 4 — pilot-agent (Go)

- **Source**: `pilot/cmd/pilot-agent/` in istio/istio.
- **Role**: PID 1 in every sidecar / gateway / waypoint pod — bootstraps Envoy, generates the static bootstrap JSON, manages SDS for cert rotation, exposes `/healthz` and `/quitquitquit`.
- **In waypoint pods specifically**: same binary, same role — bootstrap Envoy with a config that subscribes to xDS for the namespace/service the waypoint serves.
- **Reference docs**: https://istio.io/latest/docs/reference/commands/pilot-agent/

## Layer 5 — Linux threads and the kernel scheduler

- **Definitive book**: **"The Linux Programming Interface"** by Michael Kerrisk — `clone(2)`, `pthread_create`, futexes, kernel scheduling classes (CFS, RT). One of the best computing books ever written.
- **Kernel internals book**: **"Linux Kernel Development"** by Robert Love (3rd ed.) — readable, ~400 pages.
- **Canonical docs**: man pages https://man7.org/linux/man-pages/ ; kernel docs https://www.kernel.org/doc/html/latest/.
- **What "thread" means on Linux**: there is no thread vs. process distinction in the kernel. There are *tasks*. A thread is a task that shares its address space and FD table with another task — created via `clone()` with specific flags. `pthread_create` is glibc/NPTL wrapping `clone(2)`.
- **Tools to actually see threads**:
  ```sh
  ps -eLf | grep istiod         # one row per kernel task
  ls /proc/<pid>/task           # each subdir is a thread (TID)
  cat /proc/<tid>/status        # State, voluntary_ctxt_switches, ...
  cat /proc/<tid>/sched         # scheduler stats for this thread
  cat /proc/<tid>/stack         # current kernel call stack
  perf sched record -p <pid>    # then `perf sched latency`
  ```

## Layer 6 — Linux networking (iptables / CNI / sockets)

- **Book**: **"Understanding Linux Network Internals"** by Christian Benvenuti — walks the kernel stack from NIC IRQ to socket.
- TLPI has the socket-API chapters.
- **netfilter / iptables**: `iptables(8)`, `iptables-extensions(8)`. The classic tutorial is Oskar Andreasson's "Iptables Tutorial 1.2.2" (still on frozentux.net).
- **nftables** (the successor): https://wiki.nftables.org/.
- **conntrack** (the connection tracker that makes NAT and stateful rules work): `conntrack(8)`, https://conntrack-tools.netfilter.org/.
- **Sidecar mode** iptables: `tools/istio-iptables/` in istio/istio.
- **Ambient mode** socket redirect / TPROXY: `cni/pkg/` in istio/istio.
- **What to run on a kind node**:
  ```sh
  kubectl debug node/istio-ambient-worker -it --image=ubuntu \
    -- chroot /host bash
  iptables-save | less
  conntrack -L | grep <pod-ip>
  ss -lntp                       # listening sockets per process
  ss -tnp state established      # established conns + owning PID
  ```

## Layer 7 — Containers, namespaces, cgroups

- **Book**: **"Container Security"** by Liz Rice — short, accurate.
- **Canonical docs**: `namespaces(7)`, `cgroups(7)` man pages.
- **What to grok**: a "pod" is a set of containers sharing a network namespace (and others). istio-cni runs *when the pod's netns is set up*, programs socket redirect, then exits. The ztunnel pod is in the host's netns (or a privileged one) so it can intercept other pods' traffic via the per-pod redirect rules.
- **Tools**:
  ```sh
  lsns                                   # list namespaces on the node
  nsenter -t <pid> -n iptables -L        # iptables view from inside the pod's netns
  cat /proc/<pid>/ns/net                 # the netns inode
  ```

## Layer 8 — eBPF

- **Book**: **"Learning eBPF"** by Liz Rice (2023). Compact, hands-on.
- **Site**: https://ebpf.io/.
- **Brendan Gregg's site** http://www.brendangregg.com/ — bcc tools, flame graphs, the whole performance-engineering toolbox.
- **Why it matters**: istio-cni's socket-redirect is `iptables`-based today but is moving toward eBPF; the same `sk_lookup` / `sockmap` BPF programs ambient-next will use are what Cilium has been doing for years.

## Performance / observability cross-cutting

- **Book**: **"Systems Performance"** by Brendan Gregg (2nd ed.) — CPU scheduling, memory, file systems, network, all with the tools. The Gregg book to own.
- **"BPF Performance Tools"** also by Gregg — bcc/bpftrace recipes.

## Tools to keep running while you read

```sh
# What config did istiod just push to this pod?
istioctl proxy-config listeners <pod> -n <ns>
istioctl proxy-config routes    <pod> -n <ns>
istioctl proxy-config clusters  <pod> -n <ns>
istioctl proxy-config endpoints <pod> -n <ns>

# Is the pod's xDS in sync with istiod?
istioctl proxy-status

# In ambient: ztunnel's view
istioctl ztunnel-config workloads
istioctl ztunnel-config services
istioctl ztunnel-config policies

# Talk to Envoy's admin interface directly
kubectl exec -n istio-system <ingress-pod> -- curl -s localhost:15000/config_dump | jq

# Watch the iptables / socket-redirect rules on a node
kubectl debug node/<node> -it --image=ubuntu -- chroot /host bash
# then: iptables-save | grep -i istio, ss -lntp, nft list ruleset
```

## A learning order that actually works

Top-down hits walls (you keep needing lower-layer concepts). Better:

1. **TLPI chapters 1–5, 23–24, 28–30, 53–61** (basic syscalls, threads, sockets) — gets you fluent with the kernel ABI. Two weekends.
2. **Run an Istio cluster (this repo) and use `proxy-config`, `proxy-status`, `ztunnel-config` constantly.** Practice makes the theory stick.
3. **Read `pilot-discovery`'s `main.go` and one xDS resource flow end-to-end** (e.g., create a Service, see how Endpoints appear in Envoy). Half a day.
4. **Read ztunnel** (~10k LOC of Rust) end-to-end. A weekend if you know Rust.
5. **Envoy threading model post + `worker_impl.cc`** — one evening once Envoy concepts click.
6. **Iptables tutorial + read what `istio-iptables.sh` writes to chains.** Half a day with a live cluster.
7. **eBPF** later, when you want to understand where ambient is heading.

## Suggested tutorial extensions (steps 6+)

Each of these is a small step you could add to this repo that maps directly to "see the layer below":

- **"Inspect the proxy"**: have the reader `curl localhost:15000/config_dump` on the ingress gateway pod and grep for `httpbin` to find the listener/route/cluster chain that handles their request.
- **"Watch xDS in flight"**: `istioctl proxy-status`, apply an HTTPRoute or change a port, watch the version bump in real time.
- **"See the redirect rules"**: in ambient, exec into a node and dump the socket-redirect entries; show that `lsof` on a workload's outbound port lands in ztunnel, not the original destination.
- **"Trace one request end-to-end"**: enable Envoy access logs on the gateway and waypoint, send one curl, follow the X-Request-ID through three logs.
- **"AuthorizationPolicy at L4 vs L7"**: write a policy that ztunnel can enforce (port-based), then one that requires the waypoint (HTTP path-based). See the policy reach two different proxies depending on what it asks for.
- **"See Envoy's threads"**: `kubectl exec` into the gateway pod, `top -H -p $(pidof envoy)` to see Envoy's main + worker threads, then `curl localhost:15000/listeners?format=json` to dump the live listener set.
- **"Watch pilot-agent bootstrap Envoy"**: `strace -f -e trace=network -p <pilot-agent-pid>` to see the bootstrap dance when a gateway pod starts.
