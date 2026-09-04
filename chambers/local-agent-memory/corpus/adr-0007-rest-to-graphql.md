# ADR 0007: move the mobile API from REST to GraphQL

**Decision:** switch the mobile feed API from REST to GraphQL.

**Why:** the feed screen over-fetched badly on REST, pulling full objects when it
needed three fields. GraphQL lets the client ask for exactly those fields.

**Tradeoff accepted:** caching gets more complex (no more per-URL CDN caching), in
exchange for materially smaller payloads and fewer round trips on the feed screen.

**Status:** accepted, rolled out to the mobile app in the 4.2 release.
