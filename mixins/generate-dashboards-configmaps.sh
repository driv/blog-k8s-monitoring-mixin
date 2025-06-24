DASHBOARD_DIR="${1:-./generated}"

cd "$DASHBOARD_DIR" || exit 1

mkdir -p dashboards-cm
for f in dashboards/*.json; do
   name=$(basename "$f" .json);
   kubectl create configmap grafana-dashboard-$name     --from-file="$f"     -n monitoring     --dry-run=client -o yaml > dashboards-cm/$name.yaml;
done

# They need to be patched to add the label for the sidecar to pick them up
for file in dashboards-cm/*.yaml; do
   yq eval "
     .metadata.labels.grafana_dashboard = \"true\"
   " -i "$file";
done

kubectl apply -f dashboards-cm/