# Kafka Connect image with the Debezium JDBC sink (Kafka -> Postgres) and the
# Debezium Postgres source (Postgres CDC -> Kafka) connectors. The sink plugin
# bundles the Postgres JDBC driver. Built locally and loaded into kind (no
# registry needed), then referenced by the KafkaConnect CR's spec.image.
FROM quay.io/strimzi/kafka:1.1.0-kafka-4.3.0

ARG DEBEZIUM=3.1.1.Final
ARG BASE=https://repo1.maven.org/maven2/io/debezium

USER root
RUN mkdir -p /opt/kafka/plugins/debezium-jdbc /opt/kafka/plugins/debezium-postgres \
 && curl -fsSL "${BASE}/debezium-connector-jdbc/${DEBEZIUM}/debezium-connector-jdbc-${DEBEZIUM}-plugin.tar.gz" \
    | tar -xz -C /opt/kafka/plugins/debezium-jdbc --strip-components=1 \
 && curl -fsSL "${BASE}/debezium-connector-postgres/${DEBEZIUM}/debezium-connector-postgres-${DEBEZIUM}-plugin.tar.gz" \
    | tar -xz -C /opt/kafka/plugins/debezium-postgres --strip-components=1
USER 1001
