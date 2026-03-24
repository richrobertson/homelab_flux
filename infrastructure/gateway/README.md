# Infrastructure Gateway

`infrastructure/gateway/` defines ingress and external service exposure for the homelab platform.

## Purpose

- Configures shared gateway resources and route attachment points.
- Manages domain/TLS integration and external-facing service mappings.
- Provides the boundary between internal workloads and external clients.

## Subsections

- `externalServices/`: definitions for exposing selected services externally.
- `letsencrypt/`: certificate automation and ACME-related gateway resources.
- `myrobertson-com/`: domain-specific gateway/route resources.

## Operational notes

- Keep public exposure changes explicit and auditable.
- Coordinate gateway config updates with DNS and certificate dependencies.
- Validate route ownership/host collisions before applying changes.

## See also

- [Infrastructure overview](../README.md)
- [External services](externalServices/README.md)
- [Let's Encrypt integration](letsencrypt/README.md)
- [myrobertson.com domain routing](myrobertson-com/README.md)
