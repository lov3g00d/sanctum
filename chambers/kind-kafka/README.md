# Chamber: kind-kafka

A basic local Kafka on **kind + Strimzi** (operator 1.1.0, Kafka 4.3.0, KRaft), kept minimal
so it reliably comes up. The cluster spec lives in `cluster/`; the schema registry in `registry/`;
Prometheus/Grafana config in `observability/`; continuous producer/consumer apps in `apps/`.

## How it is deployed

- The **Strimzi operator** installs from its **community Helm chart** (`strimzi/strimzi-kafka-operator`).
- The Kafka cluster is a manifest (`cluster/kafka.yaml`) applied with `kubectl`: Strimzi is driven by
  custom resources and has no upstream chart for the cluster itself.

## Prerequisites

`nix develop` from the repo root (provides `kind`, `kubectl`, `helm`, `task`) and a running Docker.

## Use

`task up` brings up the base cluster. `registry`, `apps`, and `monitoring` are
optional layers on top; `monitoring` (Prometheus + Grafana) is the heaviest, so
enable it only when you want dashboards and alerts.

```sh
cd chambers/kind-kafka

# base cluster
task up         # kind + operator + Kafka
task smoke      # produce and consume on the demo topic
task status     # show the resources
task down       # delete the kind cluster

# optional layers on top of the base cluster
task registry   # Apicurio schema registry (data-contract store)
task apps       # continuous producer + consumer apps
task apps-logs  # follow the consumer app
task monitoring # Prometheus + Grafana + Kafka dashboards and alert rules
task grafana    # port-forward Grafana (admin/admin)
task connect    # Kafka Connect (Debezium JDBC sink) + Postgres

# demos, one capability each (scripts/demo/)
task ha         # kill a broker and show no data is lost
task authz      # each user can do only what its ACLs allow
task tls        # encrypted mutual-TLS produce/consume (cert identity)
task groups     # scale the consumer group and watch partitions rebalance
task schema     # the schema contract rejects bad messages at the producer   (needs registry + apps)
task evolution  # compatible schema change versioned, breaking change refused (needs registry)
task dlq        # poison message routed to the dead-letter topic              (needs registry + apps)
task alerts     # UnderReplicatedPartitions fires then resolves               (needs monitoring)
task sink       # sink a JSON topic into Postgres, no app code                (needs connect)
task cdc        # change a Postgres row, watch Debezium capture it to Kafka   (needs sink)
```

Everything lives in the `sanctum-kafka` kind cluster, so `task down` leaves nothing behind.
