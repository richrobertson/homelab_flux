# UniFi Security Reporting

This component polls UniFi gateway security alerts from the controller database,
exports Prometheus metrics, fires Alertmanager alerts for attack-like bursts, and
sends a daily morning security situational awareness email.

## Signals

- `unifi_security_threat_events_recent{window="10m|1h|24h",key,severity}`
- `unifi_security_unique_sources_recent{window,severity}`
- `unifi_security_target_events_recent{window,dst_ip,severity}`
- `unifi_security_honeypot_events_recent{window}`
- `unifi_security_scrape_success`
- `unifi_security_last_event_timestamp_seconds`

## Alerting

Alerts live in `alerts.yaml` and route through the existing kube-prometheus-stack
Alertmanager/Gotify path:

- reporter down or failed scrape
- high-severity threat block bursts
- repeated attacks against the same internal target
- many unique attacking sources
- honeypot triggers
- failed or missing daily email jobs

## Daily Email

`unifi-security-daily-email` runs at `07:30 America/Los_Angeles` and sends a
24-hour summary to `roy@myrobertson.com`.

It uses:

- UniFi SSH credentials from Vault path `secret/unifi/ssh`
- SES SMTP relay credentials from Vault path `secret/mailu/prod/ses-relay`

## Rollout Checks

After the image is published and Flux reconciles:

```sh
kubectl --context admin@prod -n monitoring get deploy,cronjob,servicemonitor,prometheusrule | rg unifi-security
kubectl --context admin@prod -n monitoring logs deploy/unifi-security-reporter
kubectl --context admin@prod -n monitoring port-forward svc/unifi-security-reporter 8080:8080
curl -fsS http://127.0.0.1:8080/metrics | rg '^unifi_security_'
```

Trigger a one-off report:

```sh
kubectl --context admin@prod -n monitoring create job --from=cronjob/unifi-security-daily-email unifi-security-daily-email-manual-$(date +%s)
```
