
# Monitoring Stack for Kubernetes on Kind

## Prerequisites

- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) installed
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) installed
- [Helm](https://helm.sh/docs/intro/install/) installed
- [docker](https://docs.docker.com/get-docker/) installed
- [Helmfile](https://github.com/roboll/helmfile#installation) installed

## Installation

Start a Kind cluster

```bash
kind create cluster --name k8s-monitoring
```

```bash
# Skip diff since we don't have the CRDs installed yet
helmfile apply --skip-diff-on-install
```

## Accessing Grafana

You can access Grafana using port-forwarding:

```bash
kubectl port-forward -n monitoring svc/grafana 80:8080 
```

grafana username and password are `admin` `admin`

## Dashboards and Rules generation

```bash
cd mixins
mkdir -p generated/dashboards

jb init

jsonnet -J vendor -S -e 'std.manifestYamlDoc((import "mixin.libsonnet").prometheusAlerts)' > generated/alerts.yml
jsonnet -J vendor -S -e 'std.manifestYamlDoc((import "mixin.libsonnet").prometheusRules)' > generated/rules.yml

jsonnet -J vendor -m generated/dashboards -e '(import "mixin.libsonnet").grafanaDashboards'
```

## Loading Rules

We can use [mimirtool](https://grafana.com/docs/mimir/latest/manage/tools/mimirtool/#installation).

```bash
kubectl port-forward -n monitoring services/mimir-ruler 8080:8080 &

mimirtool rules load --address=http://localhost:8080 --id=anonymous generated/alerts.yml 
mimirtool rules load --address=http://localhost:8080 --id=anonymous generated/rules.yml 

```

## Loading Dashboards

We can use the provided script `generate-dashboards-configmaps.sh` to load the dashboards into Grafana.

Generate the ConfigMaps for the dashboards from the `mixins` directory:

```bash
mkdir generated/dashboards-cm
for f in generated/dashboards/*.json; do
name=$(basename "$f" .json);
kubectl create configmap grafana-dashboard-$name     --from-file="$f"     -n monitoring     --dry-run=client -o yaml > generated/dashboards-cm/$name.yaml;
done
```

We need to add a label to the ConfigMaps so Grafana sidecar can recognize them as dashboards:

```bash
for file in generated/dashboards-cm/*.yaml; do
yq eval "
    .metadata.labels.grafana_dashboard = \"true\"
" -i "$file";
done
```

Now we can apply the ConfigMaps to the cluster:

```bash
kubectl apply -f generated/dashboards-cm/
```

## Expose missing Kubernetes API endpoints

Kind does not expose some of the Kubernetes API endpoints by default, so we need to patch the cluster configuration.

```bash
# Patch kube-controller-manager manifest in kind control-plane container
docker exec k8s-monitoring-control-plane sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/' /etc/kubernetes/manifests/kube-controller-manager.yaml
docker exec k8s-monitoring-control-plane sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/' /etc/kubernetes/manifests/kube-scheduler.yaml

# Restart the control-plane pods to apply the changes
kubectl -n kube-system delete pod -l tier=control-plane
```

```bash
kubectl edit -n kube-system configmaps kube-proxy
```

Update the `metricsBindAddress` to allow metrics to be exposed on all interfaces:

```yaml
metricsBindAddress: "0.0.0.0:10249"
```

```bash
# Restart the kube-proxy pod to apply the changes
kubectl -n kube-system delete pod -l k8s-app=kube-proxy
```
