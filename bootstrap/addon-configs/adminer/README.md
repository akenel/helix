Adminer Config Guide

Adminer is deployed as a lightweight DB viewer for Postgres.

Default Access
- URL: http://localhost:8080 (via Port-forward or internal browser)
- DB Name: postgres
- DB User: Stored in Vault (see /vault/credentials/postgres)
- DB Password: Same Vault location

To expose via Ingress:
Uncomment the ingress: block in values.yaml, set your desired hostname, and restart Adminer.

To customize:
Edit resource limits, service type, or add env variables for advanced DB backends.
