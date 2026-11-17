# Tekton workshop GitOps

GitOps resources for preparing a clean OpenShift 4.20 cluster for the
[Tekton workshop](https://bmeklund.github.io/tekton-workshop/modules/index.html).

The target environment provides:

- Red Hat OpenShift GitOps as the bootstrap control plane
- Red Hat OpenShift Pipelines 1.21, including Pipelines as Code
- OpenShift Web Terminal
- One OpenShift-compatible Gitea instance with `user1` through `userN`
- One isolated namespace per participant: `tekton-workshop-user1` through
  `tekton-workshop-userN`
- Namespace-local `edit` and Pipelines as Code permissions for each participant
- Default quotas and limits to keep a shared workshop cluster predictable

Start with [docs/architecture.md](docs/architecture.md), then follow
[bootstrap/README.md](bootstrap/README.md).

## Repository layout

```text
bootstrap/                    One-time OpenShift GitOps installation and root app
clusters/workshop/            Argo CD project and child Applications
platform/foundation/          Namespaces required before secrets and workloads
platform/operators/           Red Hat Operator subscriptions
charts/workshop-environment/  Local renderer for the Gitea CR and N participant namespaces
scripts/                      Runtime workshop-instance configuration
docs/                         Architecture and operational decisions
```

## Current assumptions

- The cluster is OpenShift 4.20 and has a working default `StorageClass`.
- Keycloak provisions identities `user1` through `userN` and generated
  passwords. OpenShift OAuth is already configured to use Keycloak. This
  repository grants namespace access; it does not create identities or modify
  the cluster OAuth configuration.
- The workshop guide will need to select each pre-created project during Web
  Terminal initialization rather than requesting a new project.
- The Git repository will be published at
  `https://github.com/bmeklund/tekton-workshop-gitops.git`. Update the Argo CD
  manifests before bootstrapping if the final URL differs.
- `workshop.userCount` in `charts/workshop-environment/values.yaml` is the
  single Git source for the participant count. A live Argo CD parameter or the
  helper script can override it for one running cluster without requiring a
  workshop-specific branch.

The non-sensitive, common workshop credential `openshift` is stored in Git and
used for all generated Gitea users. This is an intentional tradeoff for
disposable workshop clusters that live for only a few hours. The privileged
Gitea administrator password is still supplied separately and is not stored in
Git. Keycloak generates a unique OpenShift password for each participant.

The repository does not deploy the upstream Gitea Helm chart. The local chart
only removes repetition from our own GitOps resources; the RHDP Gitea Operator
is solely responsible for deploying and reconciling Gitea and PostgreSQL.
