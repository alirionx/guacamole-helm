# CLAUDE.md

Instructions for Claude Code in this repository.

## Project

Helm chart for Apache Guacamole (webapp + guacd + optional database). The complete functional requirements are in `docs/requirements.md` — that file is the source of truth. In case of conflicts `docs/requirements.md` wins; when something is unclear, ask instead of guessing.

## Language

All code comments, Helm templates, values documentation and Markdown files in this repository are written in English. Communication with the user is in German.

## Repository structure (target)

```
charts/guacamole/
  Chart.yaml
  values.yaml
  values.schema.json
  templates/
    _helpers.tpl
    guacamole/      # Deployment, Service, ConfigMap, HPA, PDB
    guacd/          # Deployment, Service, HPA, PDB
    database/       # schema init job, embedded StatefulSet, Service
    secrets/        # secret init job + its RBAC (Helm/Argo CD pre-sync hooks)
    auth/           # env mapping helpers for OIDC, TOTP, Duo
    network/        # Ingress, HTTPRoute, NetworkPolicies
    serviceaccount.yaml
    NOTES.txt
  files/            # shell scripts of the init jobs (checked with shellcheck)
  tests/            # helm-unittest
examples/           # example values
ci/                 # values for chart-testing
.github/workflows/
```

## Way of working

1. Read `docs/requirements.md` completely first.
2. Before implementing the auth and database configuration, check the official documentation of the pinned Guacamole version (https://guacamole.apache.org/doc/gug/), in particular the chapters on the Docker image and the individual extensions. Environment variable names have changed between versions — do not take anything from memory.
3. Build incrementally in this order and test after every step:
   1. Skeleton: guacamole + guacd, external PostgreSQL
   2. Schema init job (idempotent), secure admin password
   3. MySQL/MariaDB support
   4. Embedded database mode
   5. Ingress / HTTPRoute
   6. OIDC, then TOTP and Duo
   7. Security contexts, NetworkPolicies, PDB, HPA
   8. `extraExtensions` (init container from image as default, URL with mandatory checksum, optional image volume)
   9. `values.schema.json`, helm-docs, examples (CLI, pipelines, Argo CD, Flux), CI
   10. Low priority, only after everything else: header auth (only with enforced NetworkPolicy) and encrypted JSON incl. token script
4. Do not build features outside the scope (no LDAP, SAML, SQL Server, no operator), but keep the values structure extensible.

## Conventions

- Resource names always via the `{{ include "guacamole.fullname" . }}` helper, never hard-coded.
- Standard `app.kubernetes.io/*` labels on all resources; `component` label for guacamole, guacd, database.
- All resources namespaced; no cluster-wide resources.
- Never put secrets in values in plaintext — always `existingSecret` + `secretKey`. Pass passwords to containers as `valueFrom.secretKeyRef`.
- Abort invalid combinations (e.g. TOTP + Duo, unknown `database.type`) with `{{ fail "..." }}` and an understandable message.
- Every new value: comment in `values.yaml` in helm-docs format (`# -- description`), entry in `values.schema.json`, at least one helm-unittest.
- Checksum annotation on Deployments for referenced ConfigMaps.
- The chart must work equally via the `helm` CLI, in CI pipelines, with Argo CD and with Flux. Hooks and init jobs behave the same and idempotently in all variants; a failed init job must make `helm --wait` fail.
- No features that strictly require `lookup` (it does not work under Argo CD and `helm template`).
- Header auth must never render without a restricting NetworkPolicy.
- Activate official extensions via environment variables only, never download them additionally. Before building `extraExtensions`, read the entrypoint script of the pinned image (`GUACAMOLE_HOME` handling) so that custom JARs and automatically activated extensions do not overwrite each other.
- No dependencies on external subcharts (in particular no Bitnami charts).

## Commands

```bash
helm lint charts/guacamole
helm template test charts/guacamole -f examples/<file>.yaml
helm unittest charts/guacamole
helm template test charts/guacamole | kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
ct lint --config ct.yaml
ct install --config ct.yaml   # requires a running kind cluster
helm-docs
```

## Definition of Done (per step)

- `helm lint` without errors
- All helm-unittests green
- `kubeconform` without errors for all files in `examples/`
- README/values documentation updated
- For changes to pods: runs under Pod Security Standard `restricted`
