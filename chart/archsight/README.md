# Archsight Helm Chart

A Helm chart for deploying [Archsight](https://github.com/ionos-cloud/archsight) on Kubernetes.

## Introduction

This chart bootstraps an Archsight deployment on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager. It is designed to be flexible in how you provide the architecture "resources" (YAML files) to the application.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+

## Installing the Chart

### From OCI Registry (Recommended)

To install the chart from the GitHub Container Registry:

```bash
helm install my-archsight oci://ghcr.io/ionos-cloud/archsight/charts/archsight
```

### From Local Source

To install the chart with the release name `my-archsight` from local source:

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

## Uninstalling the Chart

To uninstall/delete the `my-archsight` deployment:

```bash
helm delete my-archsight
```
