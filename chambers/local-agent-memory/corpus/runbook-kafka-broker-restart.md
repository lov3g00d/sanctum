# Runbook: safely restart a Kafka broker

1. Drain the broker so it stops taking new leadership.
2. Wait until under-replicated partitions reach zero across the cluster.
3. Restart the broker process.
4. Confirm it rejoins the ISR and under-replicated partitions stays at zero.

**Never** restart a second broker until the first is fully back in the ISR, or you
risk taking a partition below its minimum in-sync replicas and losing writes.
