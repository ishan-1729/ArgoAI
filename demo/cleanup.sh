#!/bin/bash
# Clean up all demo apps

NAMESPACE="${DEMO_NAMESPACE:-default}"

echo "Cleaning up demo apps from namespace: $NAMESPACE"
echo ""

oc delete deployment demo-oomkilled -n $NAMESPACE --ignore-not-found
oc delete deployment demo-imagepull -n $NAMESPACE --ignore-not-found
oc delete deployment demo-missing-config -n $NAMESPACE --ignore-not-found
oc delete deployment demo-crashloop -n $NAMESPACE --ignore-not-found
oc delete deployment demo-network-issue -n $NAMESPACE --ignore-not-found
oc delete deployment demo-storage-issue -n $NAMESPACE --ignore-not-found
oc delete deployment demo-rbac-issue -n $NAMESPACE --ignore-not-found
oc delete pvc demo-nonexistent-pvc -n $NAMESPACE --ignore-not-found
oc delete sa demo-restricted-sa -n $NAMESPACE --ignore-not-found

if oc get namespace openshift-gitops >/dev/null 2>&1; then
  oc delete application demo-oomkilled -n openshift-gitops --ignore-not-found
  oc delete application demo-imagepull -n openshift-gitops --ignore-not-found
  oc delete application demo-missing-config -n openshift-gitops --ignore-not-found
  oc delete application demo-crashloop -n openshift-gitops --ignore-not-found
  oc delete application demo-network-issue -n openshift-gitops --ignore-not-found
  oc delete application demo-storage-issue -n openshift-gitops --ignore-not-found
  oc delete application demo-rbac-issue -n openshift-gitops --ignore-not-found
fi

echo ""
echo "Cleanup complete!"
