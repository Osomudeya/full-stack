#!/bin/bash

set -euo pipefail

# Print section header
print_header() {
  echo ""
  echo "============================================================"
  echo "  $1"
  echo "============================================================"
  echo ""
}

# --- Check CLI tools ---
print_header "Checking CLI tools"
for tool in az kubectl helm; do
  if ! command -v $tool &> /dev/null; then
    echo "Error: $tool is not installed."
    exit 1
  fi
done

# --- Set variables ---
RESOURCE_GROUP="app-rg"
CLUSTER_NAME="voteapp-aks"
ACR_NAME="appacr94"
NAMESPACE="memory-game"
ACR_LOGIN_SERVER="appacr94.azurecr.io"
BACKEND_IMAGE_NAME="memory-game-backend"
FRONTEND_IMAGE_NAME="memory-game-frontend"
IMAGE_TAG="${IMAGE_TAG:-latest}"         
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"

# --- Connect to AKS cluster ---
print_header "Connecting to AKS cluster"
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

# --- Create namespaces ---
print_header "Creating application and monitoring namespaces"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# --- Pre-process the deployment files to use the correct image tags ---
print_header "Pre-processing deployment files with correct image tags"
if [ -f "/tmp/application/backend-deployment.yaml" ]; then
  sed -i "s|image: $ACR_LOGIN_SERVER/$BACKEND_IMAGE_NAME:latest|image: $ACR_LOGIN_SERVER/$BACKEND_IMAGE_NAME:$IMAGE_TAG|g" /tmp/application/backend-deployment.yaml
  echo "✅ Updated backend deployment with image tag: $IMAGE_TAG"
fi

if [ -f "/tmp/application/frontend-deployment.yaml" ]; then
  sed -i "s|image: $ACR_LOGIN_SERVER/$FRONTEND_IMAGE_NAME:latest|image: $ACR_LOGIN_SERVER/$FRONTEND_IMAGE_NAME:$IMAGE_TAG|g" /tmp/application/frontend-deployment.yaml
  echo "✅ Updated frontend deployment with image tag: $IMAGE_TAG"
fi

# --- Deploy application resources ---
print_header "Applying application Kubernetes manifests"
kubectl apply -f /tmp/application/secrets.yaml
kubectl apply -f /tmp/application/postgres-deployment.yaml
kubectl apply -f /tmp/application/backend-deployment.yaml 
kubectl apply -f /tmp/application/frontend-deployment.yaml   
kubectl apply -f /tmp/application/ingress.yaml

# --- Deploy monitoring stack ---
print_header "Applying monitoring Kubernetes manifests"
kubectl apply -f /tmp/monitoring/namespace.yaml
kubectl apply -f /tmp/monitoring/prometheus/
kubectl apply -f /tmp/monitoring/grafana/
kubectl apply -f /tmp/monitoring/loki/
kubectl apply -f /tmp/monitoring/promtail/
kubectl apply -f /tmp/monitoring/kube-state-metrics/
kubectl apply -f /tmp/monitoring/alertmanager/
kubectl apply -f /tmp/monitoring/node-exporter.yaml

# kubectl apply -f /tmp/monitoring/ingress.yaml

# --- Wait for deployments to be ready ---
print_header "Waiting for application deployments to be ready"
kubectl wait --for=condition=available --timeout=300s -n $NAMESPACE deployment/backend deployment/frontend

print_header "Waiting for monitoring deployments to be ready"
kubectl wait --for=condition=available --timeout=300s -n monitoring deployment/prometheus-deployment deployment/grafana-deployment

print_header "Waiting for Loki pods to be ready"
kubectl wait --for=condition=ready pod -l app=loki -n monitoring --timeout=300s || echo "⚠️ Loki pods not fully ready, check manually."

# --- Show Access Information ---
print_header "Access Information"

APP_INGRESS_IP=$(kubectl get ingress -n $NAMESPACE memory-game-ingress -o jsonpath="{.status.loadBalancer.ingress[0].ip}")

echo "🚀 Memory Game App available at: http://$APP_INGRESS_IP"
echo ""
echo "📊 To access Grafana, Prometheus, and Alertmanager dashboards:"
echo ""
echo "🔵 Grafana Port-forward:"
echo "kubectl port-forward svc/grafana 3000:3000 -n monitoring"
echo ""
echo "🔵 Prometheus Port-forward:"
echo "kubectl port-forward svc/prometheus 9090:9090 -n monitoring"
echo ""
echo "🔵 Alertmanager Port-forward:"
echo "kubectl port-forward svc/alertmanager 9093:9093 -n monitoring"
echo ""
echo "✅ Default Grafana Login: admin / $GRAFANA_PASSWORD"

echo ""
echo "✅ Deployment complete!"