# n8n Prod Overlay

`apps/prod/n8n/` contains the production-specific n8n exposure, auth, and backup configuration.

## What this overlay adds

- public route on `n8n.myrobertson.com`
- Authelia protection for the UI with webhook path exemptions
- CNPG scheduled backups
- VolSync replication source for the CNPG PVC

## Dependencies

- shared gateway listener in [infrastructure/gateway/myrobertson-com/myrobertson-com-gateway.yaml](../../../infrastructure/gateway/myrobertson-com/myrobertson-com-gateway.yaml)
- shared backup credentials in `secret/cnpg/prod/backup-s3`
- shared VolSync Backblaze credentials for `secret/backblaze/k8s/prod/volsync`

## Notes

- The HTTPRoute will not become externally reachable unless the `.com` gateway includes the `n8n.myrobertson.com` listener.
- The production certificate secret expected by the gateway listener is `n8n-myrobertson-com-cert`.
