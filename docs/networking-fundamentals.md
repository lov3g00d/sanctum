# Networking fundamentals, traced through Nimbus

The JD calls out TCP/IP, DNS, HTTP, and distributed networks. Interviewers probe
these because they separate people who click "create load balancer" from people who
can debug why a request hangs. This doc follows one request from a partner's client
to a Nimbus pod and names what happens at each layer, then covers the pieces that
sit off the happy path.

## The request path, layer by layer

```
client ──DNS──> Cloudflare edge ──TLS/HTTP──> AWS ALB ──> Ingress ──> Service ──> Pod
```

1. **DNS resolution.** The client resolves `api.nimbus.example.com`. The authoritative answer comes from Cloudflare (the zone lives there). Because the record is proxied, the client gets a Cloudflare anycast IP, not the AWS origin. The origin is never in public DNS. That is the first security property: you cannot attack an address you cannot resolve.
2. **TCP handshake.** Client opens a connection to the Cloudflare edge: SYN, SYN-ACK, ACK. Three packets, one round trip, before any data. This is why connection reuse (keep-alive, HTTP/2 multiplexing) matters for latency.
3. **TLS handshake.** ClientHello, ServerHello, certificate, key exchange. TLS 1.3 does this in one round trip (1-RTT, or 0-RTT on resumption); TLS 1.2 took two. Cloudflare terminates TLS at the edge, then opens its own TLS connection to the origin (SSL mode "strict" so the origin cert is validated). Authenticated origin pulls mean the ALB only accepts connections presenting Cloudflare's client cert.
4. **HTTP request.** Now the actual GET/POST flows. Cloudflare applies WAF rules and rate limiting here before forwarding.
5. **AWS ALB (L7).** Terminates the Cloudflare-to-origin TLS, inspects the HTTP host/path, routes to the target group. An ALB is layer 7 (understands HTTP); an NLB is layer 4 (TCP only, faster, no header awareness). Pick ALB when you need path routing or header inspection, NLB when you need raw throughput or non-HTTP.
6. **Ingress + Service.** Inside Kubernetes the ALB targets the ingress, which maps the host to a Service. The Service is a stable virtual IP (ClusterIP); kube-proxy (or the CNI's dataplane, Cilium eBPF here in a modern cluster) load-balances across the healthy pod IPs.
7. **Pod.** The request lands on `podinfo:9898`. Response travels back up the same chain.

## DNS beyond the happy path

- **Record types you must know:** A (name to IPv4), AAAA (IPv6), CNAME (name to name, cannot coexist with other records at the apex), MX (mail), TXT (SPF/DKIM/domain verification), NS (delegation), and provider aliases (Route 53 ALIAS, Cloudflare CNAME flattening) that let you point an apex at a load balancer.
- **TTL** controls cache lifetime. Lower it before a planned migration so cutover is fast; raise it afterward to cut query load.
- **Resolution order:** stub resolver, recursive resolver (ISP or 1.1.1.1), then root, TLD, authoritative. In Kubernetes, add CoreDNS in front: pods resolve `service.namespace.svc.cluster.local` internally, and `ndots:5` in the default resolv.conf is a classic latency gotcha (every external lookup tries the search domains first).

## TCP/IP model and where things live

| Layer (TCP/IP) | Examples | Nimbus |
|----------------|----------|--------|
| Application | HTTP, DNS, gRPC | the REST API, CoreDNS |
| Transport | TCP, UDP | TCP for the API, UDP for DNS |
| Internet | IP, ICMP, routing | VPC route tables, NAT |
| Link | Ethernet, ARP | ENIs on the nodes |

TCP gives ordering, retransmission, and flow/congestion control; UDP gives none of
that and is used where latency beats reliability (DNS, QUIC's substrate). HTTP/3 runs
over QUIC over UDP, which sidesteps TCP head-of-line blocking.

## HTTP versions and status codes

- **1.1**: one request per connection at a time (pipelining never worked in practice), so browsers open many connections.
- **2**: multiplexed streams over one connection, header compression. Big win for many small requests.
- **3**: over QUIC/UDP, removes TCP head-of-line blocking, faster connection setup.
- **Status classes:** 2xx success, 3xx redirect, 4xx client error (400 malformed, 401 unauthenticated, 403 authenticated-but-forbidden, 404, 429 rate-limited), 5xx server error (500, 502 bad upstream, 503 unavailable, 504 upstream timeout). Knowing 502 vs 503 vs 504 is a debugging shortcut: 502 means the proxy reached a broken backend, 503 means nothing was available to route to, 504 means the backend was too slow.

## AWS VPC networking

- **Subnets** are AZ-scoped. Nimbus uses three tiers: public (ALB, NAT), private (EKS nodes), data (RDS, ElastiCache). Only the public tier has a route to the internet gateway.
- **NAT gateway** lets private subnets make outbound connections (pull images, call APIs) without being reachable inbound. One per AZ in prod so an AZ loss does not sever egress; one shared in dev to save cost.
- **Security groups vs NACLs:** SGs are stateful (return traffic is auto-allowed), instance-level, allow-only. NACLs are stateless (you must allow both directions), subnet-level, and support explicit deny. Best practice is SGs referencing other SGs (the app SG allows the DB SG), so rules follow workloads, not hardcoded CIDRs.
- **VPC Flow Logs** capture accepted/rejected connections for forensics and for debugging "why can't A reach B" (look for REJECT).

## Distributed-network concepts interviewers probe

- **Load balancing** L4 vs L7, health checks, connection draining on deploy.
- **Idempotency and retries:** in a distributed system every call can fail or duplicate; safe retries need idempotency keys, and retry storms need backoff + jitter and circuit breakers.
- **Timeouts and cascading failure:** an unbounded timeout downstream becomes a thread-pool exhaustion upstream. Every hop gets a timeout budget.
- **CAP in one line:** under a network partition you choose consistency or availability. RDS Multi-AZ chooses consistency (failover with a brief unavailability window); a cache read path can choose availability (serve stale).

## Debugging toolkit (name-drop with intent)

`dig`/`nslookup` for DNS, `curl -v` / `openssl s_client` for TLS and HTTP headers,
`ss`/`netstat` for sockets, `tcpdump`/Wireshark for packet capture, `mtr`/`traceroute`
for path, VPC Flow Logs and Cloudflare analytics for the managed hops. The mindset:
bisect the path, confirm each hop before blaming the next.
