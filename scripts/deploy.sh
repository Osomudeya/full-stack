#!/bin/bash

# Exit on any error
set -e

# Function to print section headers
print_header() {
  echo "============================================================"
  echo "  $1"
  echo "============================================================"
}

# Check if minikube is installed
if ! command -v minikube &> /dev/null; then
    echo "Minikube is not installed. Please install it first."
    exit 1
fi

# Check if minikube is running
if ! minikube status | grep -q "Running"; then
    print_header "Starting Minikube"
    minikube start --driver=docker --cpus=4 --memory=8g
else
    echo "Minikube is already running."
fi

# Enable the ingress addon if not already enabled
if ! minikube addons list | grep -q "ingress.*enabled"; then
    print_header "Enabling Ingress addon"
    minikube addons enable ingress
fi

# Build Docker images
print_header "Building Docker images"
cd application

echo "Building frontend image..."
docker build -t memory-game-frontend:latest ./frontend

echo "Building backend image..."
docker build -t memory-game-backend:latest ./backend

# Load images into Minikube
print_header "Loading images into Minikube"
minikube image load memory-game-frontend:latest
minikube image load memory-game-backend:latest

cd ..

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

echo "Deploying monitoring ingress..."
kubectl apply -f kubernetes/monitoring/ingress.yaml

# Update /etc/hosts
print_header "Updating /etc/hosts"
MINIKUBE_IP=$(minikube ip)
echo "Minikube IP is $MINIKUBE_IP"

if ! grep -q "memory-game.local" /etc/hosts; then
    echo "Adding memory-game.local to /etc/hosts..."
    echo "$MINIKUBE_IP memory-game.local" | sudo tee -a /etc/hosts
else
    echo "memory-game.local already exists in /etc/hosts"
fi

if ! grep -q "monitoring.local" /etc/hosts; then
    echo "Adding monitoring.local to /etc/hosts..."
    echo "$MINIKUBE_IP monitoring.local" | sudo tee -a /etc/hosts
else
    echo "monitoring.local already exists in /etc/hosts"
fi

# Wait for deployments to be ready
print_header "Waiting for deployments to be ready"
kubectl wait --for=condition=available --timeout=300s -n memory-game deployment/frontend deployment/backend deployment/postgres
kubectl wait --for=condition=available --timeout=300s -n monitoring deployment/prometheus deployment/grafana deployment/loki deployment/kube-state-metrics

print_header "Deployment complete!"
echo "Memory Game is available at: http://memory-game.local"
echo "Grafana is available at: http://monitoring.local/grafana (login: admin/admin)"
echo "Prometheus is available at: http://monitoring.local/prometheus"