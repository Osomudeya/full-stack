#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Print section header
print_header() {
  echo ""
  echo "============================================================"
  echo "  $1"
  echo "============================================================"
  echo ""
}

# Check tools
print_header "Checking CLI tools"
for tool in az kubectl helm; do
  if ! command -v $tool &> /dev/null; then
    echo "Error: $tool is not installed."
    exit 1
  fi
done

# Set variables
RESOURCE_GROUP="app-rg"
CLUSTER_NAME="voteapp-aks"
ACR_NAME="appacr94"
NAMESPACE="memory-game"
ACR_LOGIN_SERVER="appacr94.azurecr.io"
BACKEND_IMAGE_NAME="memory-game-backend"
FRONTEND_IMAGE_NAME="memory-game-frontend"
IMAGE_TAG="$GITHUB_SHA"   # Passed in as env from GitHub Actions

# Login and configure kubectl
print_header "Connecting to AKS cluster"
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

# Login to ACR
print_header "Logging into ACR"
az acr login --name "$ACR_NAME"

# Create namespace if needed
print_header "Creating namespace if it doesn't exist"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Deploy Kubernetes resources
print_header "Applying application Kubernetes manifests"
kubectl apply -f /tmp/application/namespace.yaml
kubectl apply -f /tmp/application/secrets.yaml
kubectl apply -f /tmp/application/postgres-deployment.yaml

# Update images in deployments
print_header "Updating backend and frontend deployments"
kubectl set image deployment/backend backend=$ACR_LOGIN_SERVER/$BACKEND_IMAGE_NAME:$IMAGE_TAG -n $NAMESPACE || echo "Backend deployment might not exist yet"
kubectl set image deployment/frontend frontend=$ACR_LOGIN_SERVER/$FRONTEND_IMAGE_NAME:$IMAGE_TAG -n $NAMESPACE || echo "Frontend deployment might not exist yet"

# Apply Ingress
print_header "Applying ingress"
kubectl apply -f /tmp/application/ingress.yaml

# Deploy monitoring stack (Optional)
print_header "Setting up monitoring stack"

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

print_header "Installing Prometheus & Grafana"
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin \
  --timeout 10m

helm upgrade --install loki-stack grafana/loki-stack \
  --namespace monitoring \
  --timeout 5m

# Apply Monitoring Ingress
print_header "Applying Monitoring Ingress"
kubectl apply -f /tmp/helm-aks-monitoring/monitoring-ingress-aks.yaml

# Wait for app readiness
print_header "Waiting for app and monitoring deployments to be ready"
kubectl wait --for=condition=available --timeout=300s -n $NAMESPACE deployment/backend deployment/frontend
kubectl wait --for=condition=available --timeout=300s -n monitoring deployment/prometheus-kube-prometheus-operator deployment/prometheus-grafana

# Show Access Information
print_header "Access Information"

APP_INGRESS_IP=$(kubectl get ingress -n $NAMESPACE memory-game-ingress -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
MONITORING_INGRESS_IP=$(kubectl get ingress -n monitoring monitoring-ingress -o jsonpath="{.status.loadBalancer.ingress[0].ip}")

echo "Memory Game App available at: http://$APP_INGRESS_IP"
echo "Grafana available at: http://$MONITORING_INGRESS_IP/grafana (login: admin/admin)"
echo "Prometheus available at: http://$MONITORING_INGRESS_IP/prometheus"
echo "Alertmanager available at: http://$MONITORING_INGRESS_IP/alertmanager"
