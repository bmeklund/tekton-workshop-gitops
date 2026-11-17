# Bootstrap

The only unavoidable bootstrap boundary is installing OpenShift GitOps and
registering one root `Application`. Argo CD cannot manage either resource before
the Operator and Argo CD CRDs exist. After the root Application is registered,
reconciliation starts automatically and the remaining cluster resources come
from Git.

## 1. Confirm the repository URL

The manifests use:

```text
https://github.com/bmeklund/tekton-workshop-gitops.git
```

If the repository moves, update `bootstrap/root-application.yaml`,
`clusters/workshop/project.yaml`, and `clusters/workshop/applications.yaml`.

## 2. Install OpenShift GitOps

Install Red Hat OpenShift GitOps from the OpenShift software catalog, or apply
the bootstrap manifest once as a cluster administrator:

```bash
oc apply -f bootstrap/openshift-gitops-operator.yaml
```

Wait in the OpenShift console until the Operator reports **Succeeded** and the
default `openshift-gitops` Argo CD instance is available. Terminal users can
optionally verify it with:

```bash
oc wait deployment/openshift-gitops-server \
  -n openshift-gitops \
  --for=condition=Available \
  --timeout=10m
```

## 3. Register the root Application once

In the OpenShift console, import the contents of
`bootstrap/root-application.yaml` into the `openshift-gitops` namespace. The
equivalent terminal command is:

```bash
oc apply -f bootstrap/root-application.yaml
```

This is not a recurring manual reconciliation step. It seeds the root
Application once; its automated sync then creates and maintains:

- the constrained Argo CD project;
- the `gitea` namespace through `workshop-foundation`;
- the OpenShift Pipelines and Web Terminal subscriptions;
- the pinned Gitea Operator;
- the automatically reconciled `workshop-environment` Application.

Wait for `workshop-foundation` to become **Synced/Healthy**. The `gitea`
namespace now exists and is owned by Argo CD; do not create it manually.

## 4. Supply the Gitea administrator credential

The foundation Application creates `gitea-user-password` with the common
workshop value `openshift`. This intentionally public credential is suitable
for the short-lived workshop clusters and requires no manual setup.

The privileged administrator password is different. In the OpenShift console,
select the `gitea` project and create a key/value Secret named
`gitea-admin-password` with key `adminPassword` and a private value.
The Gitea custom resource may report **Progressing** until this Secret exists;
its controller reconciles again after the Secret is created.

The optional terminal equivalent is:

```bash
read -s 'GITEA_ADMIN_PASSWORD?Gitea admin password: '
echo
oc -n gitea create secret generic gitea-admin-password \
  --from-literal=adminPassword="$GITEA_ADMIN_PASSWORD"
unset GITEA_ADMIN_PASSWORD
```

If the cluster has External Secrets, Sealed Secrets, or another approved secret
provider, manage the administrator Secret through that provider instead. That
removes this remaining manual credential step.

## 5. Adjust the participant count when needed

The committed `workshop.userCount` in
`charts/workshop-environment/values.yaml` is the only Git default and
reconciles automatically. Change that value before committing when the Git
default should change.

To override the count for only one running cluster, open the
`workshop-environment` Application in Argo CD or the OpenShift console and add
or edit its Helm parameter:

```yaml
spec:
  source:
    helm:
      parameters:
        - name: workshop.userCount
          value: "5"
  syncPolicy:
    automated:
      enabled: true
      prune: true
      selfHeal: true
```

Replace `5` with the required participant count and save the Application. Argo
CD immediately renders and reconciles the Gitea CR, Gitea users, participant
namespaces, RBAC, quotas, and limits. The root
Application is configured to preserve this instance-level count while
continuing to manage every other field from Git.

A live Helm parameter takes precedence over `values.yaml`. To return a cluster
to the Git default, remove `workshop.userCount` from the Application's Helm
parameters in Argo CD.

For administrators who prefer a terminal, the helper performs exactly the same
edit:

```bash
./scripts/configure-workshop.sh 25
```

Increasing the count is additive. Decreasing it causes Argo CD pruning to delete
higher-numbered participant namespaces and their contents. The helper therefore
requires explicit authorization:

```bash
./scripts/configure-workshop.sh 10 --allow-decrease
```

The Gitea Operator does not guarantee deletion of users above a reduced count.
After a decrease on a reused cluster, remove surplus Gitea accounts separately
or rebuild the disposable workshop environment.

The first environment sync can briefly report the Gitea kind as missing while
OLM installs the pinned Gitea Operator. Automated retry resolves this after the
CRD becomes available.
