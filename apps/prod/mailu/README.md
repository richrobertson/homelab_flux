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
  - HAProxy TCP forwarding for mail and HTTPS
  - HTTP port 80 redirect to HTTPS
  - WireGuard tunnel
  |
  v
Mailu front external Service
  - name: mailu-front-ext
  - name: mailu-front-web-ext
  - type: shared-IP LoadBalancer
  - MetalLB IP: 10.31.0.73
  |
  v
Mailu pods on the prod cluster

Outbound mail:
Mailu/Postfix -> Amazon SES SMTP relay on 587

SSO webmail:
Browser -> webmail.myrobertson.com -> myrobertson-com Gateway -> Authelia LDAP -> Mailu proxy auth
```

## What Gets Deployed

- Mailu Helm chart `2.7.0`
- A prod TLS certificate for `mail.myrobertson.net` via the existing `letsencrypt-prod` issuer and direct Cloudflare DNS-01
- Vault-backed Kubernetes Secrets for Mailu app credentials, SES relay credentials, and dynamic Helm values
- A Vault-backed home-side WireGuard peer deployment pinned to `k8s-prod-worker-2`
- VolSync replication sources for Mailu's stateful PVCs, all targeting the shared Backblaze B2 backup bucket
- A stable MetalLB address on `10.31.0.73` for Mailu mail and web services
- An Authelia-protected `webmail.myrobertson.com` path for LDAP SSO into existing Mailu accounts
- Prometheus ServiceMonitors for Dovecot and Rspamd, plus a provisioned Grafana overview dashboard
- A Mailu-specific pod network override so Dovecot trusts the real cluster pod CIDR for front-to-backend proxy auth

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
- `secret/mailu/prod/wireguard-home-peer`
  - `wg0.conf`

Terraform in `homelab_bootstrap/terraform` seeds these paths. Public `myrobertson.net` mail records live in Cloudflare.

Mailu's VolSync backup credentials are rendered from the shared Vault path `secret/backblaze/k8s/prod/volsync`.

## Initial Account

- Initial admin account: `admin@myrobertson.net`
- Retrieve the generated password from Vault or from the synced `mailu-secret` Kubernetes Secret after VSO reconciliation.
- Direct login with local Mailu credentials remains available at `mail.myrobertson.net`.
- LDAP SSO is available at `webmail.myrobertson.com` through Authelia. Mailu trusts Authelia's `Remote-Email` header and auto-creates missing Mailu accounts for authenticated LDAP users.

## DNS Handling

- Public Cloudflare records required for Mailu:
  - `mail.myrobertson.net` `A`
  - `myrobertson.net` `MX`
  - SES verification, DKIM, and MAIL FROM records
- Local `myrobertson.net` DNS should override `mail.myrobertson.net` to `10.31.0.73` for LAN clients.
  - Without that split-horizon override, local browsers hairpin through the AWS edge at `44.237.126.101` and can stall even while Mailu itself is healthy on the cluster VIP.
- Automatically managed by cert-manager in Cloudflare:
  - Temporary DNS-01 TXT records for `_acme-challenge.mail.myrobertson.net`
- Optional split-horizon/internal `myrobertson.net` records can still be managed separately if you want LAN resolution to mirror public mail DNS.
- Still manual unless you choose to automate them separately:
  - SPF, DMARC, MTA-STS, TLS-RPT, and any autodiscover/autoconfig records you want beyond the SES defaults

## Post-Apply Steps

1. Apply Terraform in `homelab_bootstrap/terraform` with the AWS mail edge enabled and SES configured.
2. Set `home_mailu_tunnel_ip = "10.31.0.73"` for the AWS edge so HAProxy forwards into the Mailu front service.
3. Seed `secret/mailu/prod/wireguard-home-peer` with the rendered `wg0.conf` if Terraform is not managing it yet.
4. Reconcile Flux and wait for `mailu-secret`, `mailu-ses-relay`, and `mailu-config` to sync from Vault.
5. Confirm `mailu-wireguard-home-peer` is `Ready` on `k8s-prod-worker-2`.
6. Confirm cert-manager can create and clean up `_acme-challenge.mail.myrobertson.net` TXT records in Cloudflare.
7. Confirm the `mailu-certificates` certificate becomes Ready.
8. Confirm `mailu-front-ext` and `mailu-front-web-ext` both share `10.31.0.73`.
9. Sign in to Mailu as `admin@myrobertson.net` and rotate any credentials if desired.

## SES Relay Notes

Mailu is configured to relay outbound mail through Amazon SES SMTP rather than sending directly from the cluster or the AWS edge.

- Relay hostname is injected from Vault as `[email-smtp.<region>.amazonaws.com]:587`
- Username and password come from the `mailu-ses-relay` Secret
- SES production sending approval is required before unrestricted outbound delivery will work.

## Observability

- Dovecot metrics are enabled through a Mailu override so Prometheus can scrape `/metrics` on port `9900`.
- Rspamd metrics are scraped from the chart's built-in `/metrics` endpoint.
- Grafana provisions a `Mailu Overview` dashboard from `infrastructure/configs/dashboards/mailu-overview.json`.
- Grafana also provisions a `Mailu Auth Troubleshooting` dashboard from `infrastructure/configs/dashboards/mailu-auth-troubleshooting.json`.
- The dashboards cover Mailu scrape health, authentication outcomes, delivery and submission activity, Rspamd scan volume, IMAP tagged reply states, and Loki log views for webmail SSO loops, Dovecot auth failures, and front-end timeout symptoms.

## Operational Flow

- Inbound mail/web: internet -> Cloudflare public DNS for `myrobertson.net` -> AWS Elastic IP -> EC2 HAProxy/WireGuard -> `mailu-front-ext` and `mailu-front-web-ext` on `10.31.0.73`
- SSO webmail: browser -> `webmail.myrobertson.com` -> `myrobertson-com-gateway` -> Authelia LDAP ext-auth -> `mailu-front` port 80 with `Remote-Email` proxy auth
- Outbound mail: Mailu -> SES SMTP -> recipient mail exchangers
