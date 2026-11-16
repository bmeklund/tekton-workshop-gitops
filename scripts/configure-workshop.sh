#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 USER_COUNT [--allow-decrease]" >&2
  echo "Example: $0 25" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

user_count=$1
allow_decrease=${2:-}
gitops_namespace=${ARGOCD_NAMESPACE:-openshift-gitops}
application_name=workshop-environment

if [[ ! $user_count =~ ^[1-9][0-9]*$ ]]; then
  echo "USER_COUNT must be a positive integer." >&2
  exit 2
fi

if [[ -n $allow_decrease && $allow_decrease != "--allow-decrease" ]]; then
  usage
  exit 2
fi

if ! oc whoami >/dev/null 2>&1; then
  echo "Log in to the OpenShift cluster with oc before running this command." >&2
  exit 1
fi

if ! oc get application "$application_name" -n "$gitops_namespace" >/dev/null 2>&1; then
  echo "Application $gitops_namespace/$application_name does not exist." >&2
  echo "Apply bootstrap/root-application.yaml and wait for the root app first." >&2
  exit 1
fi

current_count=$(oc get application "$application_name" -n "$gitops_namespace" \
  -o jsonpath='{.spec.source.helm.parameters[?(@.name=="workshop.userCount")].value}')
auto_sync_enabled=$(oc get application "$application_name" -n "$gitops_namespace" \
  -o jsonpath='{.spec.syncPolicy.automated.enabled}')
first_parameter_name=$(oc get application "$application_name" -n "$gitops_namespace" \
  -o jsonpath='{.spec.source.helm.parameters[0].name}')

if [[ $first_parameter_name != "workshop.userCount" ]]; then
  echo "Expected workshop.userCount to be the first Helm parameter." >&2
  echo "Refusing to patch an unexpected Application structure." >&2
  exit 1
fi

if [[ $auto_sync_enabled == "true" && $current_count =~ ^[1-9][0-9]*$ ]] \
  && (( user_count < current_count )) && [[ $allow_decrease != "--allow-decrease" ]]; then
  echo "Refusing to reduce the user count from $current_count to $user_count." >&2
  echo "Argo CD pruning would delete the higher-numbered participant namespaces." >&2
  echo "Re-run with --allow-decrease only after preserving any required data." >&2
  exit 1
fi

patch=$(printf '[{"op":"replace","path":"/spec/source/helm/parameters/0/value","value":"%s"},{"op":"replace","path":"/spec/syncPolicy/automated/enabled","value":true}]' \
  "$user_count")

oc patch application "$application_name" \
  -n "$gitops_namespace" \
  --type=json \
  --patch "$patch"

echo "Configured $application_name for $user_count workshop users."
echo "Argo CD automated sync is enabled. Watch progress with:"
echo "  oc get application $application_name -n $gitops_namespace -w"
