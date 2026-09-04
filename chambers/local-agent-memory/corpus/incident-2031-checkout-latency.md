# Incident 2031: checkout latency spike

**Symptom:** p99 latency on the checkout endpoint climbed to 3200ms during peak traffic.

**Root cause:** a missing database index on the `orders.customer_id` column, so the
order-history lookup did a full table scan on every checkout.

**Fix:** added a btree index on `orders.customer_id`. p99 dropped from 3200ms to 210ms
within minutes of the migration landing.

**Follow-up:** added a slow-query alert at 500ms p99 so the next regression pages us
before customers feel it.
