# Memory Game Kubernetes App with Complete Monitoring Stack

This project provides a simple memory card matching game web application with a comprehensive monitoring and observability solution. The monitoring stack includes Prometheus, Grafana, Loki, Promtail, and kube-state-metrics.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Local Development](#local-development)
- [Kubernetes Deployment (Minikube)](#kubernetes-deployment-minikube)
- [Kubernetes Deployment (AKS)](#kubernetes-deployment-aks)
- [Monitoring Stack](#monitoring-stack)
- [Access Applications](#access-applications)
- [SLIs, SLOs, and SLAs](#slis-slos-and-slas)
- [Troubleshooting](#troubleshooting)

## Architecture Overview

The application consists of:

1. **Frontend**: React application serving a memory card matching game
2. **Backend**: Node.js Express API to handle scores and provide metrics
3. **Database**: PostgreSQL to store player scores
4. **Monitoring Stack**:
   - Prometheus: Collects and stores metrics
   - Grafana: Visualizes metrics and logs
   - Loki: Aggregates and indexes logs
   - Promtail: Collects container logs and sends to Loki
   - kube-state-metrics: Exposes Kubernetes object metrics

## Prerequisites

- Docker and Docker Compose for local development
- Minikube for local Kubernetes testing
- Azure CLI and Terraform for AKS deployment
- kubectl for Kubernetes cluster management
- Helm (optional for additional tooling)

## Local Development

1. Clone the repository and navigate to the application directory:

```bash
cd memory-game-k8s-monitoring/application
```

2. Start the application using Docker Compose:

```bash
docker-compose up -d
```

3. Access the application at http://localhost:3000

## Kubernetes Deployment (Minikube)

1. Start Minikube:

```bash
minikube start --driver=docker --cpus=4 --memory=8g
```

2. Enable Ingress addon:

```bash
minikube addons enable ingress
```

3. Build and load the Docker images:

```bash
# Navigate to the application directory
cd memory-game-k8s-monitoring/application

# Build the images
docker build -t memory-game-frontend:latest ./frontend
docker build -t memory-game-backend:latest ./backend

# Load the images into Minikube
minikube image load memory-game-frontend:latest
minikube image load memory-game-backend:latest
```

4. Deploy the application:

```bash
# Create the application namespace and deploy the components
kubectl apply -f ../kubernetes/application/namespace.yaml
kubectl apply -f ../kubernetes/application/postgres-pvc.yaml
kubectl apply -f ../kubernetes/application/postgres-configmap.yaml
kubectl apply -f ../kubernetes/application/secrets.yaml
kubectl apply -f ../kubernetes/application/postgres-deployment.yaml
kubectl apply -f ../kubernetes/application/backend-deployment.yaml
kubectl apply -f ../kubernetes/application/frontend-deployment.yaml
kubectl apply -f ../kubernetes/application/ingress.yaml
```

5. Deploy the monitoring stack:

```bash
# Create the monitoring namespace and deploy the components
kubectl apply -f ../kubernetes/monitoring/namespace.yaml
kubectl apply -f ../kubernetes/monitoring/prometheus/
kubectl apply -f ../kubernetes/monitoring/grafana/
kubectl apply -f ../kubernetes/monitoring/loki/
kubectl apply -f ../kubernetes/monitoring/promtail/
kubectl apply -f ../kubernetes/monitoring/kube-state-metrics/
kubectl apply -f ../kubernetes/monitoring/ingress.yaml
```

6. Update your hosts file to access the application and monitoring stack:

```bash
# Add the following entries to /etc/hosts
echo "$(minikube ip) memory-game.local monitoring.local" | sudo tee -a /etc/hosts
```

## Kubernetes Deployment (AKS)

1. Apply your Terraform configuration to create the AKS cluster:

```bash
# Navigate to your Terraform directory and apply
terraform init
terraform apply
```

2. Connect to the AKS cluster:

```bash
az aks get-credentials --resource-group your-resource-group --name your-aks-cluster
```

3. Build and push the Docker images to a container registry:

```bash
# Log in to your Azure Container Registry
az acr login --name yourACRname

# Tag and push the images
docker build -t yourACRname.azurecr.io/memory-game-frontend:latest ./frontend
docker build -t yourACRname.azurecr.io/memory-game-backend:latest ./backend
docker push yourACRname.azurecr.io/memory-game-frontend:latest
docker push yourACRname.azurecr.io/memory-game-backend:latest
```

4. Update the Kubernetes deployment files to use your ACR images:

```bash
# Update the image references in the deployment files
sed -i 's|memory-game-frontend:latest|yourACRname.azurecr.io/memory-game-frontend:latest|g' ../kubernetes/application/frontend-deployment.yaml
sed -i 's|memory-game-backend:latest|yourACRname.azurecr.io/memory-game-backend:latest|g' ../kubernetes/application/backend-deployment.yaml
```

5. Deploy the application and monitoring stack using the same commands as for Minikube.

## Monitoring Stack

### Prometheus

Prometheus is used to collect metrics from:

- The memory game backend service (custom metrics)
- Node exporters (system metrics)
- Kubernetes API server
- kube-state-metrics (Kubernetes object metrics)
- cAdvisor (container metrics)

### Grafana

Grafana provides dashboards for:

- Kubernetes cluster overview
- Memory game application performance
- Node and container resources
- SLIs and SLOs visualization

### Loki and Promtail

Loki aggregates logs from all containers, while Promtail collects and forwards these logs to Loki. This provides a centralized logging solution accessible through Grafana.

### kube-state-metrics

kube-state-metrics exposes Kubernetes object metrics for monitoring the health and state of various Kubernetes resources.

## Access Applications

1. Access the Memory Game application:
   - Local development: http://localhost:3000
   - Minikube: http://memory-game.local
   - AKS: Use your configured domain or load balancer IP

2. Access the monitoring stack:
   - Grafana: http://monitoring.local/grafana (login with admin/admin)
   - Prometheus: http://monitoring.local/prometheus
   - Loki (through Grafana): Add as a data source in Grafana

## SLIs, SLOs, and SLAs

The monitoring system is configured to track and visualize key Service Level Indicators (SLIs) such as:

1. **Availability**: Percentage of successful requests
   - SLO: 99.9% availability (measured as non-5xx responses)

2. **Latency**: Request response time
   - SLO: 95% of requests under 300ms

3. **Error Rate**: Percentage of error responses
   - SLO: Less than 0.1% error rate

4. **Saturation**: Resource utilization
   - SLO: CPU utilization below 80%, memory below 85%

These SLIs are visualized in the Grafana dashboards and can be used to define and enforce SLOs and SLAs.

## Troubleshooting

### Common Issues

1. **Images not loading in Minikube**:
   - Ensure you've loaded the images into Minikube with `minikube image load`

2. **Database connection issues**:
   - Check the database secrets and ensure the backend can connect to PostgreSQL

3. **Ingress not working**:
   - Verify the Ingress controller is running: `kubectl -n ingress-nginx get pods`
   - Check the Ingress resource: `kubectl get ingress -A`

4. **Missing metrics in Prometheus**:
   - Verify the service annotations for Prometheus scraping
   - Check Prometheus targets in the Prometheus UI

5. **Missing logs in Loki**:
   - Verify Promtail is running as a DaemonSet on all nodes
   - Check Promtail logs for any connection issues to Loki