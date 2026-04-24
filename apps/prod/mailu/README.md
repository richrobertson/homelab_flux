# Mailu on Prod

This overlay deploys Mailu for `myrobertson.net` with `mail.myrobertson.net` as the public hostname.

## Architecture

```text
Internet
  |
  v
Public Cloudflare zone for myrobertson.net
  - A mail.myrobertson.net -> AWS mail edge Elastic IP
  - MX myrobertson.net -> mail.myrobertson.net
  - SES verification, DKIM, and MAIL FROM records
  - cert-manager writes temporary DNS-01 TXT records for mail.myrobertson.net
  |
  v
AWS EC2 mail edge
  - Elastic IP
  - HAProxy TCP forwarding
  - WireGuard tunnel
  |
  v
Mailu front external Service
  - name: mailu-front-ext
  - type: LoadBalancer
  - MetalLB IP: 10.31.0.73
  |
  v
Mailu pods on the prod cluster

Outbound mail:
Mailu/Postfix -> Amazon SES SMTP relay on 587
```

## What Gets Deployed

- Mailu Helm chart `2.7.0`
- A prod TLS certificate for `mail.myrobertson.net` via the existing `letsencrypt-prod` issuer and direct Cloudflare DNS-01
- Vault-backed Kubernetes Secrets for Mailu app credentials, SES relay credentials, and dynamic Helm values
- VolSync replication sources for Mailu's stateful PVCs, all targeting the shared Backblaze B2 backup bucket
- A stable MetalLB address on `10.31.0.73` for the Mailu external front service
- Prometheus ServiceMonitors for Dovecot and Rspamd, plus a provisioned Grafana overview dashboard

## Vault Paths

- `secret/mailu/prod/app`
  - `secret-key`
  - `initial-account-password`
  - `postgres-password`
  - `password`
  - `replication-password`
  - `roundcube-password`
- `secret/mailu/prod/ses-relay`
  - `relay-username`
  - `relay-password`
- `secret/mailu/prod/config`
  - `values.yaml`

Terraform in `homelab_bootstrap/terraform` seeds these paths. Public `myrobertson.net` mail records live in Cloudflare.

Mailu's VolSync backup credentials are rendered from the shared Vault path `secret/backblaze/k8s/prod/volsync`.

## Initial Account

- Initial admin account: `admin@myrobertson.net`
- Retrieve the generated password from Vault or from the synced `mailu-secret` Kubernetes Secret after VSO reconciliation.

## DNS Handling

- Public Cloudflare records required for Mailu:
  - `mail.myrobertson.net` `A`
  - `myrobertson.net` `MX`
  - SES verification, DKIM, and MAIL FROM records
- Automatically managed by cert-manager in Cloudflare:
  - Temporary DNS-01 TXT records for `_acme-challenge.mail.myrobertson.net`
- Optional split-horizon/internal `myrobertson.net` records can still be managed separately if you want LAN resolution to mirror public mail DNS.
- Still manual unless you choose to automate them separately:
  - SPF, DMARC, MTA-STS, TLS-RPT, and any autodiscover/autoconfig records you want beyond the SES defaults

## Post-Apply Steps

1. Apply Terraform in `homelab_bootstrap/terraform` with the AWS mail edge enabled and SES configured.
2. Set `home_mailu_tunnel_ip = "10.31.0.73"` for the AWS edge so HAProxy forwards into the Mailu front service.
3. Use the Terraform WireGuard output to finish the home-side peer config.
4. Reconcile Flux and wait for `mailu-secret`, `mailu-ses-relay`, and `mailu-config` to sync from Vault.
5. Confirm cert-manager can create and clean up `_acme-challenge.mail.myrobertson.net` TXT records in Cloudflare.
6. Confirm the `mailu-certificates` certificate becomes Ready.
7. Confirm `mailu-front-ext` receives `10.31.0.73`.
8. Sign in to Mailu as `admin@myrobertson.net` and rotate any credentials if desired.

## SES Relay Notes

Mailu is configured to relay outbound mail through Amazon SES SMTP rather than sending directly from the cluster or the AWS edge.

- Relay hostname is injected from Vault as `[email-smtp.<region>.amazonaws.com]:587`
- Username and password come from the `mailu-ses-relay` Secret
- The AWS EC2 edge is only for inbound mail and HTTPS termination/forwarding in this design

## Observability

- Dovecot metrics are enabled through a Mailu override so Prometheus can scrape `/metrics` on port `9900`.
- Rspamd metrics are scraped from the chart's built-in `/metrics` endpoint.
- Grafana provisions a `Mailu Overview` dashboard from `infrastructure/configs/dashboards/mailu-overview.json`.
- The dashboard covers Mailu scrape health, authentication outcomes, delivery and submission activity, Rspamd scan volume, and IMAP tagged reply states.

## Operational Flow

- Inbound mail/web: internet -> Cloudflare public DNS for `myrobertson.net` -> AWS Elastic IP -> EC2 HAProxy -> WireGuard -> `mailu-front-ext` on `10.31.0.73`
- Outbound mail: Mailu -> SES SMTP -> recipient mail exchangers
