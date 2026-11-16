# Bootstrap

The cluster bootstrap has one unavoidable imperative boundary: Argo CD cannot
install and start reconciling itself.

## 1. Check the repository URL

The provisional repository URL is:

```text
https://github.com/bmeklund/tekton-workshop-gitops.git
```

If the final URL differs, update `bootstrap/root-application.yaml` and
`clusters/workshop/applications.yaml` before applying anything.

## 2. Install OpenShift GitOps

Log in as a cluster administrator and apply the first-stage manifest:

```bash
oc apply -f bootstrap/openshift-gitops-operator.yaml
oc wait subscription/openshift-gitops-operator \
  -n openshift-gitops-operator \
  --for=jsonpath='{.status.state}'=AtLatestKnown \
  --timeout=10m
oc wait deployment/openshift-gitops-server \
  -n openshift-gitops \
  --for=condition=Available \
  --timeout=10m
```

If `gitops-1.21` is unavailable in the target catalog, inspect available
channels before changing the manifest:

```bash
oc get packagemanifest openshift-gitops-operator \
  -n openshift-marketplace \
  -o jsonpath='{.status.channels[*].name}'
```

## 3. Create Gitea credentials outside Git

The namespace can be created before Argo CD; Argo CD will adopt and manage it.

```bash
oc create namespace gitea --dry-run=client -o yaml | oc apply -f -

read -s 'GITEA_ADMIN_PASSWORD?Gitea admin password: '
echo
oc -n gitea create secret generic gitea-admin-password \
  --from-literal=adminPassword="$GITEA_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | oc apply -f -
unset GITEA_ADMIN_PASSWORD

read -s 'WORKSHOP_USER_PASSWORD?Common Gitea workshop-user password: '
echo
oc -n gitea create secret generic gitea-user-password \
  --from-literal=userPassword="$WORKSHOP_USER_PASSWORD" \
  --dry-run=client -o yaml | oc apply -f -
unset WORKSHOP_USER_PASSWORD
```

For a permanent environment, replace this manual secret handoff with the
organization's secret manager integration.

For this workshop, enter `openshift` at the Gitea workshop-user password prompt.
The value is sent directly to the Secret and is not stored in a Kubernetes YAML
file. Gitea validates this common local credential, while OpenShift console and
CLI authentication use each participant's unique password through the existing
Keycloak-backed OpenShift OAuth configuration. The GitOps repository does not
install an HTPasswd identity provider.

## 4. Start GitOps reconciliation

```bash
oc apply -f bootstrap/root-application.yaml
oc wait application/tekton-workshop-cluster \
  -n openshift-gitops \
  --for=jsonpath='{.status.sync.status}'=Synced \
  --timeout=10m
```

The workshop environment Application is created with automated sync paused so
that the default participant count cannot create resources accidentally.
Configure this workshop instance at runtime without creating a Git branch:

```bash
./scripts/configure-workshop.sh 25
oc get applications -n openshift-gitops -w
```

The count is stored on the live `workshop-environment` Application and drives
both Gitea account creation and participant namespaces. The root Application is
configured to preserve this runtime parameter while continuing to reconcile all
other child-Application fields from Git.

Increasing the count adds users and namespaces. Reducing it causes Argo CD to
prune higher-numbered namespaces and their contents, so the script refuses a
decrease unless it is explicitly authorized:

```bash
./scripts/configure-workshop.sh 10 --allow-decrease
```

The Gitea Operator creates missing numbered users but does not provide this
workflow with a guaranteed account-deletion mechanism. After decreasing the
count on a reused cluster, separately verify and remove any higher-numbered
Gitea accounts, or rebuild the disposable workshop environment.

The first environment sync can briefly report the Gitea kind as missing while
OLM installs the pinned Gitea Operator. Automated retry resolves this after the
CRD becomes available.
