# Requirements: Helm Chart for Apache Guacamole

Status: Draft v0.3 · Date: 2026-10-22

## 1. Goal

A self-built, production-ready Helm chart for Apache Guacamole that
- can be rolled out conveniently via GitOps (Argo CD / Flux),
- makes the database backend and auth extensions configurable through `values.yaml`,
- allows several independent Guacamole instances in the same cluster (one instance per namespace).

The Apache project provides no official Helm chart. Existing community charts serve as reference only; nothing is copied from them or included as a dependency.

## 2. Architecture decision

- **Helm chart** (no operator). Rationale: Guacamole is stateless apart from the database; there is no lifecycle that justifies a controller. Helm fits GitOps and multi-instance-per-namespace directly.
- A later operator (Kubebuilder) is explicitly **not** part of this scope. The chart should, however, be structured cleanly enough that an operator could later render it or adopt its templates.

## 3. Components

| Component | Implementation |
|---|---|
| `guacamole` (webapp, Tomcat) | Deployment, image `guacamole/guacamole`, horizontally scalable (mind session affinity at the ingress) |
| `guacd` (proxy daemon) | Separate Deployment + Service, image `guacamole/guacd`, scalable |
| Database | Bundled (embedded, default) or external, see section 4 |
| Secret init | Kubernetes Job (Helm hook `pre-install,pre-upgrade`, Argo CD `PreSync`), creates missing Secrets, see section 4.4 |
| DB schema init | Kubernetes Job (Helm hook `post-install,post-upgrade`, Argo CD `Sync`), see section 4.3. Not `PostSync`: Argo CD runs PostSync hooks only once all resources are healthy, which an Ingress without load balancer status never becomes; the job waits for the database itself. |
| Exposure | Ingress **and** Gateway API (`HTTPRoute`), both optional and switchable |

Both images are pinned to the same Guacamole version (`appVersion` in the chart, default: current stable version, 1.6.0).

## 4. Database backend

### 4.1 Supported types
- PostgreSQL
- MySQL / MariaDB

Exactly one type is active: `database.type: postgresql | mysql`.

### 4.2 Operating modes
- `database.mode: embedded` (default): the chart ships a single-replica database (PostgreSQL or MariaDB, depending on `database.type`) as a StatefulSet with PVC. No dependency on Bitnami subcharts. `helm install` works without any prerequisites.
- `database.mode: external`: connection to an existing database (e.g. CloudNativePG, managed DB). Host, port, database name, user; password **only** via an existing Secret (`existingSecret` + key).
- Embedded is meant to be solid for DevOps engineers, not "enterprise-ready": single replica StatefulSet with PVC, no clustering, no backups. HA and disaster recovery are the operator's responsibility (or use `external`, e.g. CloudNativePG). No dependencies on other Helm charts.
- The embedded database uses a superuser (password from Secret) and a separate application user that owns the Guacamole database; the webapp and the schema job only use the application user.
- Version policy for the embedded database:
  1. The major version is pinned per chart major version (PostgreSQL 17, MariaDB 11.4 LTS); chart releases only bump patch/minor versions.
  2. A database major version change requires a new chart major version and a documented migration path (dump/restore). No automatic `pg_upgrade`.
  3. A guard in the database pod compares the version of the persisted data with the image and aborts with a clear message on a mismatch (PostgreSQL: `PG_VERSION`). MariaDB upgrades in place via `MARIADB_AUTO_UPGRADE`.
  4. CI upgrade test per chart release: install the previous chart version, create data, upgrade, verify data and login.

### 4.3 Schema initialization
- A Job loads the schema if it does not exist yet (idempotent: first check whether the table `guacamole_user` exists).
- The schema is generated from the official image (`/opt/guacamole/bin/initdb.sh --postgresql|--mysql`), not duplicated in the chart.
- After initialization the initial admin (`guacadmin`) must receive a random or Secret-provided password; the default `guacadmin/guacadmin` must never stay active.
- Source of the admin password: `auth.admin.existingSecret` + `auth.admin.secretKey` (optional). Without `existingSecret`, the secret init job (4.4) generates a random password.
- Overwrite rule: the job sets the password (a) on the initial initialization and (b) on later runs only if `guacadmin` still has the default password. A password changed in the UI is not overwritten. With `auth.admin.enforcePassword: true` the password is set from the Secret on every run (e.g. when managed by Vault/External Secrets).
- The password hash is computed in SQL (PostgreSQL `sha256()`, MySQL `SHA2()`), without additional software.
- Upgrades with schema changes: upgrade scripts are **not** run automatically in phase 1. The docs describe the manual path; the job aborts with a clear error message if the schema version does not match (where determinable).

### 4.4 Secret initialization
- Applies to all passwords the chart has to provide: the `guacadmin` password, and for `embedded` additionally the database password and, if needed, the database superuser password.
- For each password: if `existingSecret` is set, it is used (the job checks that Secret and key exist and otherwise aborts with a clear message). Otherwise the job creates a Secret `<fullname>-…` with a random value, unless it already exists. No password is ever rendered by a template (no `randAlphaNum`, no `lookup`) → deterministic rendering, Argo CD compatible.
- Secrets referenced by the user must be of type `Opaque`; documented in `values.yaml` and the README.
- The job runs before the workloads (the embedded database needs its password on first start), with its own ServiceAccount (token mount only here) and a namespaced Role (`get`/`create` on Secrets). The workloads keep `automountServiceAccountToken: false`.
- Secrets created by the job are not managed by Helm and survive `helm uninstall` (consistent with the remaining PVC of the embedded database). Docs: manual cleanup; NOTES.txt shows how to read the admin password.

## 5. Authentication / extensions

Configured through a structured `auth.*` block in `values.yaml`, which the chart translates into the environment variables of the official image. Secrets exclusively via `existingSecret` references.

### 5.1 Database auth
Always active (users, connections and permissions live in the database).

### 5.2 OIDC / SSO
- `auth.oidc.enabled`
- Issuer, authorization endpoint, JWKS endpoint, client ID, redirect URI, scopes, username claim, groups claim
- Integration test against Dex; documentation examples for Keycloak, Microsoft Entra ID, Authentik
- Optional: automatically create users in the database (`*_AUTO_CREATE_ACCOUNTS` or similar; verify variable names against the docs of the pinned version)

### 5.3 Second factor
- `auth.totp.enabled` (TOTP)
- `auth.duo.enabled` (Duo; API hostname, client ID, client secret from a Secret)
- TOTP and Duo are mutually exclusive → validation in the template (`fail`)

### 5.4 HTTP header auth (priority: low)
- `auth.header.enabled`, header name configurable (default `REMOTE_USER`).
- Provides the identity only; connections/permissions still come from the database.
- Used behind a forward-auth proxy (oauth2-proxy, Authentik, Authelia, Pomerium, Traefik ForwardAuth). Documentation example with oauth2-proxy + Traefik ForwardAuth.
- **Security requirement:** if `auth.header.enabled: true`, the chart must enforce a NetworkPolicy that only allows ingress traffic to the guacamole pod from configured sources (ingress controller or proxy namespace/labels). No configured sources → `fail`. Documentation warning that the proxy must strip a header sent by the client.
- Header auth and OIDC may be active at the same time, but the docs recommend using only one of them.

### 5.5 Encrypted JSON auth (priority: low)
- `auth.json.enabled`
- Shared secret (128 bit, 32 hex characters) exclusively from `existingSecret`; validate the format in the template where possible.
- Trusted networks (CIDR list) configurable; default empty = no restriction, with a documentation note that restricting is recommended.
- Purpose: temporary, non-persisted connections that an external system (portal, ticket system, script) passes to `/api/tokens` as signed + encrypted JSON.
- Example under `examples/`: a small script (Bash/OpenSSL or Python) that creates a valid token and opens a session — doubles as an integration test.
- Documentation note: the key allows arbitrary targets → restrict guacd egress via NetworkPolicy.

### 5.6 Order / priority
The extension load order (e.g. OIDC before DB) must be configurable, if supported by the image (`EXTENSION_PRIORITY`).

### 5.7 Generic fallback
- `guacamole.extraEnv` and `guacamole.extraProperties` (set as `guacamole.properties` entries or environment properties), so that options not modelled by the chart can be used without changing the chart.

### 5.7a Providing extensions
- **Official extensions** (JDBC, OIDC, TOTP, Duo, header, JSON, …) are included in the official image and are activated exclusively via environment variables. No download, no init container.
- **Additional extensions** via `guacamole.extraExtensions` (list). Each entry has exactly one source:
  - `image` (**default/recommended**): an init container from an OCI image containing the JARs (path in the image configurable, default `/extensions`) copies them into an `emptyDir`. Image by tag or digest; `imagePullPolicy` and `imagePullSecrets` configurable.
  - `url`: an init container downloads the JAR; `sha256` is mandatory, otherwise `fail`. A failed download or checksum prevents the pod from starting.
  - `imageVolume` (optional): mount via Kubernetes image volumes without an init container; only usable if cluster and runtime support it, documented accordingly. Container runtimes (containerd) only support directories as image volume `subPath`, so the directory with the JARs is mounted as `GUACAMOLE_HOME/extensions`; an `imageVolume` entry must therefore be the only entry (`fail` otherwise).
- The `emptyDir` is mounted so that the additional JARs end up in `GUACAMOLE_HOME/extensions/` **without** interfering with the automatic activation of the official extensions by the entrypoint script. Verified against the 1.6.0 entrypoint: `GUACAMOLE_HOME` (`/etc/guacamole`) is only used as a template; its `extensions/` entries are symlinked into the generated home under `/tmp`, alongside the env-activated official extensions.
- Init containers run with the same restrictive security contexts as the main containers.
- Compatible with `readOnlyRootFilesystem: true`: all paths written by the entrypoint (e.g. `/tmp`, temporary `GUACAMOLE_HOME`) are mounted as `emptyDir`.
- Docs: example Dockerfile for an extension image; note on alternative custom images (`FROM guacamole/guacamole`), which the chart also supports via `guacamole.image`.
- ConfigMaps as a source for JARs are not supported (1 MiB limit).

### 5.8 Out of scope for phase 1
LDAP/AD, SAML, CAS, SQL Server. The values structure should, however, allow adding these later as further `auth.<name>` blocks.

## 6. Multi-instance

- One instance = one Helm release in one namespace.
- All resources namespaced, **no** cluster-wide resources (no ClusterRoles, no CRDs).
- Resource names via the `fullname` helper, so that even several releases in the same namespace do not collide.
- Documentation example: Argo CD `ApplicationSet` that creates one instance per namespace/team with its own values file.

## 7. Network & exposure

- guacamole Service: `type` configurable (`ClusterIP` default, `LoadBalancer` supported; incl. `loadBalancerIP`/`loadBalancerSourceRanges`, annotations, `externalTrafficPolicy`).
- Ingress (`kind: Ingress`; className, annotations, hosts) optional, TLS optional.
- Gateway API `HTTPRoute` (`kind: HTTPRoute`) optional, TLS optional. Decision: the `Gateway` is operated externally; the `HTTPRoute` attaches to it via `parentRefs` (incl. `sectionName` for the HTTPS listener). TLS (certificate) is configured on the Gateway listener; the chart does not create its own Gateway.
- The WebSocket tunnel must work; documentation notes for Traefik and Gateway API (timeouts). No documentation of ingress-nginx annotations (project retired).
- Sticky sessions when `guacamole.replicaCount > 1` (annotation examples).
- Context path configurable, default: Guacamole served at `/` (instead of `/guacamole`).
- Behind a reverse proxy: configure the RemoteIpValve / `X-Forwarded-For` correctly.
- `NetworkPolicy` optional (default off): guacamole → guacd, guacamole → DB, ingress → guacamole; guacd may connect outbound to the target systems (configurable CIDRs/ports).

## 8. Security

- Pods run as non-root, `readOnlyRootFilesystem` where possible, `allowPrivilegeEscalation: false`, capabilities dropped, `seccompProfile: RuntimeDefault`.
- Compatible with Pod Security Standard `restricted`.
- No plaintext secrets in `values.yaml` or in the rendered release; only `existingSecret` references. Missing Secrets are created at runtime by the secret init job (section 4.4); no `lookup`.
- Dedicated ServiceAccount, `automountServiceAccountToken: false`.

## 9. Operations

- `resources`, `nodeSelector`, `tolerations`, `affinity`, `topologySpreadConstraints`, `podAnnotations/Labels` per component.
- Liveness/readiness probes for guacamole (HTTP) and guacd (TCP).
- `PodDisruptionBudget` optional.
- `HorizontalPodAutoscaler` optional for guacamole and guacd.
- Log level configurable (guacd and webapp).
- Session recordings: optional, phase 2 (requires an RWX volume shared by guacd and guacamole).

## 10. Deployment paths: CLI, pipeline, GitOps

The chart must work equally well in all three variants; no feature may work only with one tool.

- **CLI:** `helm upgrade --install <release> oci://... -n <ns> --create-namespace -f values.yaml --wait --atomic` works without further preparation (apart from the referenced Secrets). `--set` is usable for all values.
- **Pipeline:** example workflows under `examples/pipelines/` for GitHub Actions and GitLab CI (lint → `helm diff` → deploy). Reliable exit codes: a failed init job makes `helm --wait` fail.
- **GitOps:** Argo CD and Flux (`HelmRelease`), examples under `examples/gitops/`.
- Chart distributed as an OCI artifact (ghcr.io/alirionx/charts/guacamole) and as packaged chart (`.tgz` + `.sha256`) attached to each GitHub release. No classic Helm repository (GitHub Pages) — decided not needed.
- Init jobs: Helm hooks under Helm, `argocd.argoproj.io/hook` annotations under Argo CD; behavior idempotent and identical in both cases.

### General requirements
- Deterministic rendering (no random values on each `helm template`).
- Hooks designed to work under Argo CD (add `argocd.argoproj.io/hook` annotations, or use a Job with `ttlSecondsAfterFinished` + idempotent logic instead of pure Helm hooks).
- Checksum annotations on Deployments so that config changes trigger a rollout.

## 11. Quality & deliverables

- `values.schema.json` validating all values.
- README with a complete values table (generated with `helm-docs`).
- Example values under `examples/`: minimal (external PostgreSQL), embedded MySQL (lab), OIDC with Keycloak + TOTP, header auth behind oauth2-proxy, encrypted JSON with token script, Argo CD ApplicationSet for multi-instance, Flux HelmRelease, CI pipelines.
- Tests:
  - `helm lint` and `helm template` for all examples
  - Unit tests with `helm-unittest`
  - Schema/manifest validation with `kubeconform`
  - Integration test with `kind` + `chart-testing` (`ct install`): login page reachable, DB init successful
  - OIDC integration test against Dex (template: setup in the `capi-navigator` repository)
- CI: GitHub Actions (lint, tests, release as OCI artifact to ghcr.io).
- Versioning: SemVer for the chart, `appVersion` = Guacamole version.

## 12. Open points

- [x] Target Kubernetes version: ≥ 1.29 (`imageVolume` optional only, depending on cluster support)
- [ ] Registry/namespace for the chart (proposal: ghcr.io/<user>/charts)
- [ ] Ingress controller in the target cluster (Traefik, Cilium/Gateway API?)
- [ ] Session recordings in phase 1 or 2?
- [ ] Declarative connections (e.g. a job that writes connections from values into the database) — wanted?
- [x] Chart license: Apache-2.0 (`LICENSE`, Chart annotation `artifacthub.io/license`)
- [ ] TLS for external databases (`database.external.tls`: SSL mode, CA/client certificates for webapp and schema job) — deferred, after phase 1 scope
