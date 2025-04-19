#!/bin/bash
# Install monitoring stack using Helm

# Exit on error
set -e

echo "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo "Creating monitoring namespace if it doesn't exist..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "Installing Prometheus Stack..."
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values ../helm-local/monitoring/prometheus-values.yaml

echo "Installing Loki Stack..."
helm install loki-stack grafana/loki-stack \
  --namespace monitoring \
  --values ../helm-local/monitoring/loki-values.yaml

echo "Applying monitoring ingress..."
kubectl apply -f ../helm-local/monitoring/monitoring-ingress.yaml

echo "Done! Monitoring stack installed."