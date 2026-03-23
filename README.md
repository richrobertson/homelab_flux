# homelab_flux

GitOps repository for managing a two-environment Kubernetes homelab (`staging` and `prod`) with Flux, Kustomize, Helm, Istio, and Prometheus/Grafana.

## Related repositories

This repository is one part of a shared homelab stack:

- [homelab_bootstrap](https://github.com/richrobertson/homelab_bootstrap) - first-stage cluster bootstrap/orchestration before Flux management.
- [homelab_ansible](https://github.com/richrobertson/homelab_ansible) - host and node configuration automation outside Kubernetes manifests.
- [homelab_flux](https://github.com/richrobertson/homelab_flux) - in-cluster GitOps state (apps, controllers, configs, and gateway resources).

## What this repository manages

- **Cluster bootstrapping and reconciliation** through Flux Kustomizations under `clusters/`.
- **Infrastructure controllers** (Istio, Prometheus stack, storage, device plugins, etc.) under `infrastructure/controllers/`.
- **Infrastructure config resources** (issuers, load balancer pools, alerts, dashboards, gateway-related config) under `infrastructure/configs/`.
- **Gateway and external routing** under `infrastructure/gateway/`.
- **Applications** (media stack, auth, sync, etc.) via Helm releases under `apps/`.

## Environments

- `clusters/staging` reconciles:
  - `./infrastructure/p0`
  - `./infrastructure/controllers`
  - `./infrastructure/configs`
  - `./infrastructure/gateway`
  - `./apps/staging`
- `clusters/prod` reconciles:
  - `./infrastructure/p0`
  - `./infrastructure/controllers`
  - `./infrastructure/configs`
  - `./infrastructure/gateway`
  - `./apps/prod`

Flux dependency chain is intentionally ordered:

`infra-p0 -> infra-controllers -> infra-configs -> infra-gateway -> apps`

## Quick Start

### 1) Set cluster context

Make sure your `kubectl` context targets the correct environment before any Flux command.

```bash
kubectl config get-contexts
kubectl config use-context <staging-context>
```

### 2) Bootstrap Flux (first-time only)

Use the matching cluster path for each environment:

```bash
# staging
flux bootstrap github \
  --owner=<github-user> \
  --repository=homelab_flux \
  --branch=main \
  --path=clusters/staging

# prod
flux bootstrap github \
  --owner=<github-user> \
  --repository=homelab_flux \
  --branch=main \
  --path=clusters/prod
```

### 3) Reconcile after changes

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization infra-configs -n flux-system --with-source
flux reconcile kustomization infra-gateway -n flux-system --with-source
flux reconcile kustomization apps -n flux-system --with-source
```

### 4) Verify rollout

```bash
flux get kustomizations -A
flux get helmreleases -A
kubectl get pods -A
```

## Repository layout

```text
.
├── apps/
│   ├── base/                 # shared app HelmRepository/HelmRelease and base manifests
│   ├── staging/              # staging overlays/patches
│   └── prod/                 # prod overlays/patches
├── clusters/
│   ├── staging/              # Flux entrypoints for staging
│   └── prod/                 # Flux entrypoints for prod
├── infrastructure/
│   ├── p0/                   # foundational infra (CRDs, namespaces, VSO/NFD bootstrap)
│   ├── controllers/          # cluster controllers managed by Helm/Flux
│   ├── configs/              # policy/config objects, dashboards, alerts, cert config
│   └── gateway/              # ingress/gateway config and external service routing
├── scripts/
│   └── validate.sh           # local/CI schema and kustomize validation
└── README.md
```

## Tooling prerequisites

Recommended local tooling:

- `kubectl`
- `flux`
- `kustomize` (v5+)
- `yq` (v4+)
- `kubeconform`

For repo validation, use:

```bash
./scripts/validate.sh
```

This script:

1. Downloads Flux CRD schemas.
2. Lints YAML structure with `yq`.
3. Validates `clusters/*` manifests with `kubeconform`.
4. Builds every kustomization and validates rendered output.

## Day-2 operations

### Reconcile after merge

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization infra-configs -n flux-system --with-source
flux reconcile kustomization infra-gateway -n flux-system --with-source
flux reconcile kustomization apps -n flux-system --with-source
```

(Use the specific environment context before running these commands.)

### Check Flux health

```bash
flux get kustomizations -A
flux get helmreleases -A
kubectl get gitrepositories -A
```

### Check cluster health quickly

```bash
kubectl get nodes
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp | tail -50
```

## Observability notes

- Grafana dashboards are provisioned from ConfigMaps in `infrastructure/configs/`.
- Gateway case metrics and service drilldowns are maintained as JSON dashboards in:
  - `infrastructure/configs/dashboards/istio-gateway-case-metrics.json`
  - `infrastructure/configs/dashboards/istio-gateway-service-drilldown.json`
- Prometheus rules for gateway alerting are defined in:
  - `infrastructure/configs/istio-gateway-alerts.yaml`

## Change workflow

1. Make changes in feature branch or directly in `main` (depending on your workflow).
2. Run `./scripts/validate.sh` locally.
3. Commit and push.
4. Let Flux reconcile on interval, or force reconcile for faster rollout.
5. Verify resources in-cluster and in Grafana/Prometheus as needed.

## Safety and conventions

- Keep environment-specific values in `apps/prod`, `apps/staging`, and cluster overlays.
- Keep reusable manifests in `apps/base` and shared infra directories.
- Prefer small, focused commits for easier Flux rollback/debugging.
- Validate before merge to avoid reconciling broken manifests.

## License

See `LICENSE`.
