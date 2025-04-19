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
kubectl apply -f kubernetes/application/postgres-pvc.yaml
kubectl apply -f kubernetes/application/postgres-configmap.yaml
kubectl apply -f kubernetes/application/secrets.yaml
kubectl apply -f kubernetes/application/postgres-deployment.yaml
kubectl apply -f kubernetes/application/postgres-service.yaml

echo "Deploying backend..."
kubectl apply -f kubernetes/application/backend-deployment.yaml
kubectl apply -f kubernetes/application/backend-service.yaml

echo "Deploying frontend..."
kubectl apply -f kubernetes/application/frontend-deployment.yaml
kubectl apply -f kubernetes/application/frontend-service.yaml

echo "Deploying ingress..."
kubectl apply -f kubernetes/application/ingress.yaml

# Deploy the monitoring stack
print_header "Deploying the monitoring stack"
echo "Creating monitoring namespace..."
kubectl apply -f kubernetes/monitoring/namespace.yaml

echo "Deploying Prometheus..."
kubectl apply -f kubernetes/monitoring/prometheus/configmap.yaml
kubectl apply -f kubernetes/monitoring/prometheus/rbac.yaml
kubectl apply -f kubernetes/monitoring/prometheus/deployment.yaml
kubectl apply -f kubernetes/monitoring/prometheus/service.yaml

echo "Deploying Grafana..."
kubectl apply -f kubernetes/monitoring/grafana/configmap.yaml
kubectl apply -f kubernetes/monitoring/grafana/secret.yaml
kubectl apply -f kubernetes/monitoring/grafana/deployment.yaml
kubectl apply -f kubernetes/monitoring/grafana/service.yaml

echo "Deploying Loki..."
kubectl apply -f kubernetes/monitoring/loki/deployment.yaml

echo "Deploying Promtail..."
kubectl apply -f kubernetes/monitoring/promtail/daemonset.yaml

echo "Deploying kube-state-metrics..."
kubectl apply -f kubernetes/monitoring/kube-state-metrics/rbac.yaml
kubectl apply -f kubernetes/monitoring/kube-state-metrics/deployment.yaml
kubectl apply -f kubernetes/monitoring/kube-state-metrics/service.yaml

echo "Deploying node-exporter..."
kubectl apply -f kubernetes/monitoring/node-exporter.yaml

echo "Deploying AlertManager..."
kubectl apply -f kubernetes/monitoring/alertmanager/configmap.yaml
kubectl apply -f kubernetes/monitoring/alertmanager/deployment.yaml
kubectl apply -f kubernetes/monitoring/alertmanager/service.yaml

echo "Deploying monitoring ingress..."
kubectl apply -f kubernetes/monitoring/ingress.yaml

# Wait for deployments to be ready
print_header "Waiting for deployments to be ready"
kubectl wait --for=condition=available --timeout=300s -n memory-game deployment/frontend deployment/backend deployment/postgres
kubectl wait --for=condition=available --timeout=300s -n monitoring deployment/prometheus deployment/grafana deployment/loki deployment/kube-state-metrics

# Get ingress IP or hostname
print_header "Application access information"
INGRESS_IP=$(kubectl get ingress -n memory-game memory-game-ingress -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
MONITORING_IP=$(kubectl get ingress -n monitoring monitoring-ingress -o jsonpath="{.status.loadBalancer.ingress[0].ip}")

echo "Memory Game is available at: http://$INGRESS_IP"
echo "Grafana is available at: http://$MONITORING_IP/grafana (login: admin/admin)"
echo "Prometheus is available at: http://$MONITORING_IP/prometheus"
echo "Loki is available at: http://$MONITORING_IP/loki"

print_header "Deployment to AKS complete!"