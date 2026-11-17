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

current_count=$(oc get namespaces \
  -l workshop.redhat.com/participant \
  -o name | wc -l | tr -d '[:space:]')

if [[ $current_count =~ ^[1-9][0-9]*$ ]] \
  && (( user_count < current_count )) && [[ $allow_decrease != "--allow-decrease" ]]; then
  echo "Refusing to reduce the user count from $current_count to $user_count." >&2
  echo "Argo CD pruning would delete the higher-numbered participant namespaces." >&2
  echo "Re-run with --allow-decrease only after preserving any required data." >&2
  exit 1
fi

parameter_index=-1
parameter_count=0
while IFS= read -r parameter_name; do
  [[ -z $parameter_name ]] && continue
  if [[ $parameter_name == "workshop.userCount" ]]; then
    parameter_index=$parameter_count
  fi
  ((parameter_count += 1))
done < <(oc get application "$application_name" -n "$gitops_namespace" \
  -o jsonpath='{range .spec.source.helm.parameters[*]}{.name}{"\n"}{end}')

if (( parameter_index >= 0 )); then
  patch=$(printf '[{"op":"replace","path":"/spec/source/helm/parameters/%d/value","value":"%s"},{"op":"add","path":"/spec/syncPolicy/automated/enabled","value":true}]' \
    "$parameter_index" "$user_count")
elif (( parameter_count == 0 )); then
  patch=$(printf '[{"op":"add","path":"/spec/source/helm/parameters","value":[{"name":"workshop.userCount","value":"%s"}]},{"op":"add","path":"/spec/syncPolicy/automated/enabled","value":true}]' \
    "$user_count")
else
  patch=$(printf '[{"op":"add","path":"/spec/source/helm/parameters/-","value":{"name":"workshop.userCount","value":"%s"}},{"op":"add","path":"/spec/syncPolicy/automated/enabled","value":true}]' \
    "$user_count")
fi

oc patch application "$application_name" \
  -n "$gitops_namespace" \
  --type=json \
  --patch "$patch"

echo "Configured $application_name for $user_count workshop users."
echo "Argo CD automated sync is enabled. Watch progress with:"
echo "  oc get application $application_name -n $gitops_namespace -w"
