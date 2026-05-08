from agent.engine import _router


def _route(signals: dict) -> str:
    agent_id, _, _ = _router.route_heuristic(signals)
    return agent_id


def test_runtime_routes_image_pull():
    assert _route({
        "healthStatus": "Degraded",
        "syncStatus": "Synced",
        "podStatuses": [{"stateReason": "ImagePullBackOff"}],
    }) == "runtime"


def test_runtime_pod_state_beats_generic_out_of_sync():
    assert _route({
        "healthStatus": "Progressing",
        "syncStatus": "OutOfSync",
        "warningEvents": [{
            "reason": "Failed",
            "message": (
                'Failed to pull image "registry.access.redhat.com/ubi9/ubi-minimal:bad": '
                "manifest unknown"
            ),
        }],
        "podStatuses": [{"stateReason": "ImagePullBackOff"}],
    }) == "runtime"


def test_crashloop_logs_do_not_override_runtime_without_specialist_signal():
    assert _route({
        "healthStatus": "Progressing",
        "syncStatus": "OutOfSync",
        "warningEvents": [{
            "reason": "BackOff",
            "message": "Back-off restarting failed container crash",
        }],
        "podStatuses": [{"stateReason": "CrashLoopBackOff", "lastTerminatedReason": "Error"}],
        "preloadedLogs": {
            "pod": "demo-crashloop-abc",
            "logs": "ERROR: Database connection failed - ECONNREFUSED 10.0.0.1:5432",
        },
    }) == "runtime"


def test_config_routes_missing_configmap():
    assert _route({
        "healthStatus": "Degraded",
        "syncStatus": "Synced",
        "warningEvents": [{
            "reason": "Failed",
            "message": 'Error: configmap "nonexistent-config-map" not found',
        }],
        "podStatuses": [{"stateReason": "CreateContainerConfigError"}],
    }) == "config"


def test_network_routes_probe_failure():
    assert _route({
        "healthStatus": "Degraded",
        "syncStatus": "Synced",
        "warningEvents": [{
            "reason": "Unhealthy",
            "message": "Liveness probe failed: dial tcp 10.128.0.37:8080: connect: connection refused",
        }],
    }) == "network"


def test_storage_routes_pvc_provisioning_failure():
    assert _route({
        "healthStatus": "Degraded",
        "syncStatus": "Synced",
        "warningEvents": [{
            "reason": "ProvisioningFailed",
            "message": "storageclass.storage.k8s.io nonexistent-storage-class not found",
        }],
    }) == "storage"


def test_rbac_routes_forbidden_failed_create():
    assert _route({
        "healthStatus": "Degraded",
        "syncStatus": "Synced",
        "warningEvents": [{
            "reason": "FailedCreate",
            "message": "Error creating: pods is forbidden: unable to validate against any security context constraint",
        }],
    }) == "rbac"


def test_rbac_log_signal_beats_generic_crashloop_state():
    assert _route({
        "healthStatus": "Degraded",
        "syncStatus": "OutOfSync",
        "warningEvents": [{
            "reason": "BackOff",
            "message": "Back-off restarting failed container rbac-check",
        }],
        "podStatuses": [{"stateReason": "CrashLoopBackOff"}],
        "preloadedLogs": {
            "pod": "demo-rbac-issue-abc",
            "logs": (
                'secrets is forbidden: User "system:serviceaccount:default:demo-restricted-sa" '
                'cannot list resource "secrets" in API group "" in the namespace "default"'
            ),
        },
    }) == "rbac"
