# Kubernetes (Helm)

A Helm chart for deploying [Archsight](https://github.com/ionos-cloud/archsight) on Kubernetes.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+

## Installing the Chart

### From OCI Registry (Recommended)

```bash
helm install my-archsight oci://ghcr.io/ionos-cloud/archsight/charts/archsight
```

### From Local Source

```bash
helm install my-archsight ./chart/archsight
```

## Configuration

The following table lists the configurable parameters of the Archsight chart and their default values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Docker image repository | `archsight` |
| `image.tag` | Docker image tag | `""` (uses appVersion) |
| `service.type` | Kubernetes Service type | `ClusterIP` |
| `service.port` | Service port | `80` |
| `ingress.enabled` | Enable Ingress resource | `false` |
| `app.resourcesDir` | Directory where app looks for resources | `/resources` |

### Resource Management Strategies

The most important configuration is how you provide your architecture YAML files to the application. This is controlled by the `content.type` parameter.

#### 1. ConfigMap (Simple / Static)
Best for small deployments where the architecture definitions rarely change or are small enough to fit in a ConfigMap (1MB limit).

```yaml
content:
  type: configMap
  configMap:
    create: true
    data:
      analysis.yaml: |
        apiVersion: architecture/v1alpha1
        kind: Analysis
        metadata:
          name: MyAnalysis
        # ... content ...
```

#### 2. Persistence (Manual Management)
Mounts a Persistent Volume. You are responsible for putting files into this volume (e.g., manually copying them or having another process write to it).

```yaml
content:
  type: persistence
  persistence:
    enabled: true
    size: 1Gi
```

#### 3. EmptyDir + Git Sync (GitOps / Recommended)
Uses an `emptyDir` volume that is shared between the main container and init containers. This allows you to fetch your architecture definitions from a Git repository at startup.

**Example values.yaml configuration (Public Repo):**

```yaml
content:
  type: emptyDir

initContainers:
  - name: git-sync
    image: alpine/git
    # Clone your architecture repo into /resources
    args: ["clone", "--depth", "1", "https://github.com/my-org/my-architecture.git", "/resources"]
    volumeMounts:
      - name: resources
        mountPath: /resources
```

**Example values.yaml configuration (Private Repo):**

To use a private repository, create a Kubernetes Secret containing your git token (e.g., `git-credentials` with key `token`) and reference it:

```yaml
content:
  type: emptyDir

initContainers:
  - name: git-sync
    image: alpine/git
    env:
      - name: GIT_TOKEN
        valueFrom:
          secretKeyRef:
            name: git-credentials
            key: token
    command: ["/bin/sh", "-c"]
    # Use the env var in the URL so the token is not exposed in the pod spec
    args:
      - "git clone https://oauth2:$GIT_TOKEN@github.com/my-org/my-private-repo.git /resources"
    volumeMounts:
      - name: resources
        mountPath: /resources
```

### Sidecars (Auto-Refresh)

If you want your application to update dynamically when the git repository changes (without restarting the pod), you can add a sidecar container that periodically pulls changes.

**Example (Private Repo with 60s Refresh Loop):**

```yaml
sidecars:
  - name: git-refresher
    image: alpine/git
    env:
      - name: GIT_TOKEN
        valueFrom:
          secretKeyRef:
            name: git-credentials
            key: token
    command: ["/bin/sh", "-c"]
    args:
      - |
        cd /resources
        # Set the remote URL with the token to ensure authentication
        git remote set-url origin "https://oauth2:${GIT_TOKEN}@github.com/my-org/my-private-repo.git"
        while true; do
          git pull
          sleep 60
        done
    volumeMounts:
      - name: resources
        mountPath: /resources
```

## Rolling Restart via Maintenance Endpoint

For simple deployments where you want to trigger a pod restart (and image re-pull) without `kubectl`, you can enable the `POST /maintenance/restart` endpoint.

**How it works:**
1. A `POST` to `/maintenance/restart` signals the server to shut down gracefully.
2. Kubernetes detects the pod has exited and restarts it (`restartPolicy: Always`).
3. With `imagePullPolicy: Always`, the new image is pulled on every pod start.

**Enable in values.yaml:**

```yaml
image:
  pullPolicy: Always  # Pull a fresh image on every pod restart

restart:
  enabled: true
  token: "your-secret-token"   # Stored as a Kubernetes Secret automatically
```

The chart creates a `Secret` containing the token and injects it as `ARCHSIGHT_RESTART_TOKEN`
into the container. To use a pre-existing Secret instead:

```yaml
restart:
  enabled: true
  existingSecret: "my-restart-secret"
  secretKey: "restart-token"       # key inside the Secret (default)
```

**Trigger a restart:**

```bash
curl -X POST http://<archsight-service>/maintenance/restart \
  -H "X-Restart-Token: your-secret-token"
# → {"ok":true,"message":"Server shutting down"}
```

The pod exits, Kubernetes restarts it, and the new image is pulled automatically.

When the endpoint is disabled (the default), it returns `404 Restart endpoint is disabled`.
When a token is configured and the header is missing or wrong, it returns `401 Invalid or missing restart token`.

**Configuring the shutdown delay:**

The server waits 2 seconds (default) before sending SIGTERM to allow the response to be
flushed. Override with the `ARCHSIGHT_RESTART_SHUTDOWN_DELAY` environment variable (seconds, float):

```yaml
env:
  - name: ARCHSIGHT_RESTART_SHUTDOWN_DELAY
    value: "3.0"
```

> **Security note:** Restrict access to this endpoint at the network/ingress level. The `--restart-token` flag adds a shared-secret check in code, but network-level restrictions (e.g., internal-only ingress, NetworkPolicy) are the primary defence for publicly reachable deployments.

## Uninstalling the Chart

```bash
helm delete my-archsight
```
