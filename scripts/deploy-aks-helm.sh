#!/bin/bash

# Exit on any error
set -e

# Function to print section headers
print_header() {
  echo "============================================================"
  echo "  $1"
  echo "============================================================"
}

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "kubectl is not installed. Please install it first."
    exit 1
fi

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
    echo "Helm is not installed. Please install it first."
    exit 1
fi

# Variables - adjust these as needed
RESOURCE_GROUP="your-resource-group"
CLUSTER_NAME="your-aks-cluster"
ACR_NAME="yourACRname"
LOCATION="eastus"

# Login to Azure (comment out if already logged in)
print_header "Logging in to Azure"
az login

# Set the subscription (adjust as needed)
print_header "Setting subscription"
az account set --subscription "Your Subscription Name"

# Connect to AKS cluster
print_header "Connecting to AKS cluster"
az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME

# Build and push Docker images
print_header "Building and pushing Docker images to ACR"
cd application

# Login to ACR
az acr login --name $ACR_NAME

echo "Building and pushing frontend image..."
docker build -t $ACR_NAME.azurecr.io/memory-game-frontend:latest ./frontend
docker push $ACR_NAME.azurecr.io/memory-game-frontend:latest

echo "Building and pushing backend image..."
docker build -t $ACR_NAME.azurecr.io/memory-game-backend:latest ./backend
docker push $ACR_NAME.azurecr.io/memory-game-backend:latest

cd ..

# Update Kubernetes deployment files to use ACR images
print_header "Updating deployment files to use ACR images"
sed -i "s|memory-game-frontend:latest|$ACR_NAME.azurecr.io/memory-game-frontend:latest|g" kubernetes/application/frontend-deployment.yaml
sed -i "s|memory-game-backend:latest|$ACR_NAME.azurecr.io/memory-game-backend:latest|g" kubernetes/application/backend-deployment.yaml

# Deploy the application
print_header "Deploying the application"
echo "Creating application namespace..."
kubectl apply -f kubernetes/application/namespace.yaml

echo "Deploying PostgreSQL..."
# kubectl apply -f kubernetes/application/postgres-pvc.yaml
# kubectl apply -f kubernetes/application/postgres-configmap.yaml
kubectl apply -f kubernetes/application/secrets.yaml
kubectl apply -f kubernetes/application/postgres-deployment.yaml
# kubectl apply -f kubernetes/application/postgres-service.yaml

echo "Deploying backend..."
kubectl apply -f kubernetes/application/backend-deployment.yaml
# kubectl apply -f kubernetes/application/backend-service.yaml

echo "Deploying frontend..."
kubectl apply -f kubernetes/application/frontend-deployment.yaml
# kubectl apply -f kubernetes/application/frontend-service.yaml

echo "Deploying ingress..."
kubectl apply -f kubernetes/application/ingress.yaml

# Deploy the monitoring stack using Helm charts
print_header "Deploying the monitoring stack using Helm charts"

# Create monitoring namespace
echo "Creating monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repositories
echo "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Prometheus Stack (includes Grafana, Alertmanager)
echo "Installing Prometheus Stack with Helm..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values helm-aks-monitoring/monitoring/prometheus-values-aks.yaml \
  --set grafana.adminPassword=admin \
  --timeout 10m

# Install Loki Stack (includes Promtail)
echo "Installing Loki Stack with Helm..."
helm upgrade --install loki-stack grafana/loki-stack \
  --namespace monitoring \
  --values helm-aks-monitoring/monitoring/loki-values-aks.yaml \
  --timeout 5m

# Deploy monitoring ingress
echo "Deploying monitoring ingress..."
kubectl apply -f helm-aks-monitoring/monitoring-ingress-aks.yaml

# Wait for deployments to be ready
print_header "Waiting for deployments to be ready"
kubectl wait --for=condition=available --timeout=300s -n memory-game deployment/frontend deployment/backend deployment/postgres
kubectl wait --for=condition=available --timeout=300s -n monitoring deployment/prometheus-kube-prometheus-operator deployment/prometheus-grafana

# Get ingress IP or hostname
print_header "Application access information"
INGRESS_IP=$(kubectl get ingress -n memory-game memory-game-ingress -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
MONITORING_IP=$(kubectl get ingress -n monitoring monitoring-ingress -o jsonpath="{.status.loadBalancer.ingress[0].ip}")

echo "Memory Game is available at: http://$INGRESS_IP"
echo "Grafana is available at: http://$MONITORING_IP/grafana (login: admin/admin)"
echo "Prometheus is available at: http://$MONITORING_IP/prometheus"
echo "Alertmanager is available at: http://$MONITORING_IP/alertmanager"

print_header "Deployment to AKS complete!"
echo ""
echo "Note: Loki logs can be accessed through Grafana. The Grafana dashboard has been"
echo "automatically configured with the Loki data source."
echo ""
echo "To check if everything is running properly:"
echo "kubectl get pods -n monitoring"