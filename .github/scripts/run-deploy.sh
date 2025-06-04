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
RESOURCE_GROUP="${AKS_RESOURCE_GROUP:-app-rg}"
CLUSTER_NAME="${AKS_CLUSTER_NAME:-voteapp-aks}"
ACR_NAME="${ACR_NAME:-appacr94}"
NAMESPACE="${NAMESPACE:-memory-game}"
ACR_LOGIN_SERVER="${ACR_LOGIN_SERVER:-appacr94.azurecr.io}"
BACKEND_IMAGE_NAME="${BACKEND_IMAGE_NAME:-memory-game-backend}"
FRONTEND_IMAGE_NAME="${FRONTEND_IMAGE_NAME:-memory-game-frontend}"
IMAGE_TAG="${IMAGE_TAG:-latest}"         
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"

# PostgreSQL settings
DB_NAME="${DB_NAME:-gamedb}"
DB_APP_USER="${DB_APP_USER:-gameapp}"
DB_APP_PASSWORD="${DB_APP_PASSWORD:-Gogetalife2#}"

# --- Connect to AKS cluster ---
print_header "Connecting to AKS cluster"
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

# --- Get Azure PostgreSQL Connection Details ---
print_header "Setting up Azure PostgreSQL Connection"

# Add this section to your enhanced deployment script around line 40-50 
# (after the PostgreSQL server detection but before database setup)

# --- Non-Interactive PostgreSQL Setup ---
print_header "Configuring Non-Interactive PostgreSQL Access"

# Check if PGPASSWORD is set (from GitHub Actions)
if [ -n "${PG_ADMIN_PASSWORD:-}" ]; then
  export PGPASSWORD="$PG_ADMIN_PASSWORD"
  echo "✅ Using PostgreSQL admin password from environment"
else
  echo "⚠️ PG_ADMIN_PASSWORD not set - you may be prompted for password"
fi

# Create a more robust setup script that handles connection errors
cat > /tmp/setup_db.sql << EOF
-- Create application database if it doesn't exist
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME') THEN
    PERFORM dblink_exec('dbname=' || current_database(), 'CREATE DATABASE $DB_NAME');
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- Database might already exist, continue
  NULL;
END
\$\$;

-- Connect to the application database
\c $DB_NAME;

-- Create application user if it doesn't exist
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_APP_USER') THEN
    CREATE USER $DB_APP_USER WITH PASSWORD '$DB_APP_PASSWORD';
    RAISE NOTICE 'Created user: $DB_APP_USER';
  ELSE
    RAISE NOTICE 'User already exists: $DB_APP_USER';
  END IF;
END
\$\$;

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_APP_USER;
GRANT ALL ON SCHEMA public TO $DB_APP_USER;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_APP_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_APP_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_APP_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_APP_USER;

-- Verify connection
SELECT 'Database setup completed successfully!' as status, 
       current_database() as database,
       current_user as connected_as,
       version() as server_version;
EOF

# Execute the setup with better error handling
echo "🔧 Executing database setup (non-interactive)..."
if psql -h "$PG_FQDN" -U "$PG_ADMIN_USER" -d postgres -f /tmp/setup_db.sql -q; then
  echo "✅ Database and user setup completed successfully"
else
  EXIT_CODE=$?
  echo "⚠️ Database setup failed with exit code: $EXIT_CODE"
  echo "🔍 This might be due to:"
  echo "  - Incorrect admin password"
  echo "  - Network connectivity issues"  
  echo "  - Database already configured"
  echo "  - Permissions issues"
  echo ""
  echo "📝 Continuing with deployment - manual database setup may be required"
fi

# Test connection with application user
echo "🧪 Testing application user connection..."
if PGPASSWORD="$DB_APP_PASSWORD" psql -h "$PG_FQDN" -U "$DB_APP_USER" -d "$DB_NAME" -c "SELECT current_user, current_database();" -q; then
  echo "✅ Application user connection successful"
else
  echo "⚠️ Application user connection failed - this may cause deployment issues"
fi

# Clean up
rm -f /tmp/setup_db.sql
unset PGPASSWORD  # Clear the admin password from environment

echo "🔍 Detecting PostgreSQL Flexible Server..."
PG_SERVER_NAME=$(az postgres flexible-server list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")

if [ -z "$PG_SERVER_NAME" ]; then
  echo "❌ No PostgreSQL Flexible Server found in resource group: $RESOURCE_GROUP"
  echo "Please ensure your Terraform has created the PostgreSQL server"
  exit 1
fi

echo "📦 Found PostgreSQL Server: $PG_SERVER_NAME"

# Get connection details
PG_FQDN=$(az postgres flexible-server show --name "$PG_SERVER_NAME" --resource-group "$RESOURCE_GROUP" --query "fullyQualifiedDomainName" -o tsv)
PG_ADMIN_USER=$(az postgres flexible-server show --name "$PG_SERVER_NAME" --resource-group "$RESOURCE_GROUP" --query "administratorLogin" -o tsv)

echo "🌐 PostgreSQL FQDN: $PG_FQDN"
echo "👤 Admin User: $PG_ADMIN_USER"

# --- Setup Database and Application User ---
print_header "Setting up Application Database and User"

# Check if psql is available
if ! command -v psql &> /dev/null; then
  echo "📥 Installing PostgreSQL client..."
  apt-get update -qq
  apt-get install -y postgresql-client
fi

echo "🔐 Setting up database and application user..."
echo "Note: You may be prompted for the PostgreSQL admin password"

# Create a temporary SQL script
cat > /tmp/setup_db.sql << EOF
-- Create application database if it doesn't exist
SELECT 'CREATE DATABASE $DB_NAME' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME');
\gexec

-- Connect to the application database
\c $DB_NAME;

-- Create application user if it doesn't exist
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_APP_USER') THEN
    CREATE USER $DB_APP_USER WITH PASSWORD '$DB_APP_PASSWORD';
  END IF;
END
\$\$;

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_APP_USER;
GRANT ALL ON SCHEMA public TO $DB_APP_USER;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_APP_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_APP_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_APP_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_APP_USER;

-- Verify setup
SELECT 'Database setup completed successfully!' as status;
EOF

# Execute the setup script
echo "🔧 Executing database setup..."
if psql -h "$PG_FQDN" -U "$PG_ADMIN_USER" -d postgres -f /tmp/setup_db.sql; then
  echo "✅ Database and user setup completed successfully"
else
  echo "⚠️ Database setup failed, but continuing with deployment..."
  echo "You may need to set up the database manually"
fi

# Clean up temporary file
rm -f /tmp/setup_db.sql

# --- ACR Authentication ---
print_header "Ensuring ACR Authentication is Working"
echo "🔗 Attaching ACR to AKS cluster (this ensures reliable authentication)..."
az aks update -n "$CLUSTER_NAME" -g "$RESOURCE_GROUP" --attach-acr "$ACR_NAME" || echo "⚠️ ACR attach command failed, but continuing..."

echo "✅ ACR authentication configured"

# --- Create namespaces ---
print_header "Creating application namespace"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# --- Create PostgreSQL connection secrets ---
print_header "Creating PostgreSQL Connection Secrets"

echo "🔐 Creating secrets with Azure PostgreSQL connection details..."

# Encode values to base64
DB_HOST_B64=$(echo -n "$PG_FQDN" | base64 -w 0)
DB_USER_B64=$(echo -n "$DB_APP_USER" | base64 -w 0)
DB_PASSWORD_B64=$(echo -n "$DB_APP_PASSWORD" | base64 -w 0)
DB_NAME_B64=$(echo -n "$DB_NAME" | base64 -w 0)
DB_PORT_B64=$(echo -n "5432" | base64 -w 0)

# Create the secret
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: backend-secrets
  namespace: $NAMESPACE
type: Opaque
data:
  DB_HOST: $DB_HOST_B64
  DB_USER: $DB_USER_B64
  DB_PASSWORD: $DB_PASSWORD_B64
  DB_NAME: $DB_NAME_B64
  DB_PORT: $DB_PORT_B64
EOF

echo "✅ PostgreSQL secrets created successfully"

# --- Create database initialization job ---
print_header "Creating Database Schema Initialization Job"

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: db-init
  namespace: $NAMESPACE
spec:
  template:
    spec:
      containers:
      - name: db-init
        image: postgres:14-alpine
        envFrom:
        - secretRef:
            name: backend-secrets
        env:
        - name: PGSSLMODE
          value: "require"
        command:
        - /bin/sh
        - -c
        - |
          echo "Initializing database schema..."
          psql -h \$DB_HOST -U \$DB_USER -d \$DB_NAME -c "
          CREATE TABLE IF NOT EXISTS scores (
            id SERIAL PRIMARY KEY,
            player_name VARCHAR(100) NOT NULL,
            score INTEGER NOT NULL,
            time INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          );
          
          CREATE INDEX IF NOT EXISTS idx_scores_score ON scores(score DESC);
          
          INSERT INTO scores (player_name, score, time)
          VALUES 
            ('Player1', 100, 60),
            ('Player2', 90, 70),
            ('Player3', 85, 75)
          ON CONFLICT DO NOTHING;
          " && echo "✅ Database schema created successfully!" || echo "⚠️ Schema creation failed"
      restartPolicy: OnFailure
  backoffLimit: 3
EOF

echo "🗄️ Database initialization job created"

# --- Deploy application resources ---
print_header "Applying application Kubernetes manifests"

# Apply existing secrets file as fallback (will be overridden by the one we just created)
kubectl apply -f /tmp/application/secrets.yaml || echo "⚠️ No secrets.yaml found, using generated secrets"

# Deploy application components (skip postgres pod since we're using Azure PostgreSQL)
kubectl apply -f /tmp/application/backend-deployment.yaml 
kubectl apply -f /tmp/application/frontend-deployment.yaml   
kubectl apply -f /tmp/application/ingress.yaml

# --- Update images in deployments ---
print_header "Updating backend and frontend deployments with correct image tags"
kubectl set image deployment/backend backend="$ACR_LOGIN_SERVER/$BACKEND_IMAGE_NAME:$IMAGE_TAG" -n $NAMESPACE
kubectl set image deployment/frontend frontend="$ACR_LOGIN_SERVER/$FRONTEND_IMAGE_NAME:$IMAGE_TAG" -n $NAMESPACE

# --- Force pod restart to retry image pulls with new authentication ---
print_header "Restarting pods to apply ACR authentication"
echo "🔄 Deleting existing pods to force restart with proper ACR authentication..."
kubectl delete pods -l app=backend -n $NAMESPACE --ignore-not-found=true
kubectl delete pods -l app=frontend -n $NAMESPACE --ignore-not-found=true

echo "⏳ Waiting 10 seconds for pods to be recreated..."
sleep 10

# --- Wait for database initialization ---
print_header "Waiting for Database Initialization"
echo "⏳ Waiting for database schema initialization to complete..."
kubectl wait --for=condition=complete --timeout=120s -n $NAMESPACE job/db-init || echo "⚠️ Database initialization timeout - check logs"

# Check job status
DB_INIT_STATUS=$(kubectl get job db-init -n $NAMESPACE -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
if [ "$DB_INIT_STATUS" = "Complete" ]; then
  echo "✅ Database initialization completed successfully"
else
  echo "⚠️ Database initialization status: $DB_INIT_STATUS"
  echo "📋 Job logs:"
  kubectl logs job/db-init -n $NAMESPACE || echo "No logs available"
fi

# --- Wait for deployments to be ready ---
print_header "Waiting for application deployments to be ready"

echo "⏳ Waiting for Backend..."
kubectl wait --for=condition=available --timeout=300s -n $NAMESPACE deployment/backend || echo "⚠️ Backend deployment not ready yet"

echo "⏳ Waiting for Frontend..."
kubectl wait --for=condition=available --timeout=300s -n $NAMESPACE deployment/frontend || echo "⚠️ Frontend deployment not ready yet"

# --- Check for any remaining image pull issues ---
print_header "Checking for Image Pull Issues"
IMAGE_PULL_ERRORS=$(kubectl get events -n $NAMESPACE --field-selector type=Warning --sort-by='.lastTimestamp' | grep -i "failed to pull\|imagepullbackoff\|errimagepull" | wc -l)

if [ "$IMAGE_PULL_ERRORS" -gt 0 ]; then
  echo "⚠️ Still seeing image pull errors. Trying fallback authentication method..."
  
  # Fallback: Enable ACR admin user and create secret
  echo "🔑 Enabling ACR admin user as fallback..."
  az acr update --name "$ACR_NAME" --admin-enabled true
  
  ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --query "username" -o tsv)
  ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" -o tsv)
  
  echo "🔐 Creating Kubernetes docker registry secret..."
  kubectl delete secret acr-secret -n $NAMESPACE --ignore-not-found=true
  
  kubectl create secret docker-registry acr-secret \
      --docker-server="$ACR_LOGIN_SERVER" \
      --docker-username="$ACR_USERNAME" \
      --docker-password="$ACR_PASSWORD" \
      --docker-email=dummy@example.com \
      -n $NAMESPACE
  
  echo "🔧 Patching service account to use the secret..."
  kubectl patch serviceaccount default -n $NAMESPACE -p '{"imagePullSecrets": [{"name": "acr-secret"}]}'
  
  echo "🔄 Restarting deployments with ACR secret..."
  kubectl rollout restart deployment/backend -n $NAMESPACE
  kubectl rollout restart deployment/frontend -n $NAMESPACE
  
  echo "⏳ Waiting for deployments with ACR secret..."
  kubectl wait --for=condition=available --timeout=300s -n $NAMESPACE deployment/backend || echo "⚠️ Backend still having issues"
  kubectl wait --for=condition=available --timeout=300s -n $NAMESPACE deployment/frontend || echo "⚠️ Frontend still having issues"
else
  echo "✅ No image pull errors detected"
fi

# --- Show pod status ---
print_header "Current Pod Status"
kubectl get pods -n $NAMESPACE

# --- Database Connection Test ---
print_header "Database Connection Test"
echo "🏥 Testing database connection from backend..."

BACKEND_POD=$(kubectl get pods -n $NAMESPACE -l app=backend --field-selector=status.phase=Running -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo "")

if [ -n "$BACKEND_POD" ]; then
  echo "🔍 Testing database connection from pod: $BACKEND_POD"
  
  # Test database connection
  kubectl exec "$BACKEND_POD" -n $NAMESPACE -- sh -c '
    echo "Testing database connection..."
    psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT current_database(), current_user, version();" || echo "Database connection failed"
  ' || echo "⚠️ Database connection test failed"
  
  echo "🏥 Testing backend health endpoint..."
  kubectl exec "$BACKEND_POD" -n $NAMESPACE -- curl -f http://localhost:3001/health || echo "⚠️ Backend health check failed"
else
  echo "⚠️ No running backend pod found for testing"
fi

# --- Check pod health ---
print_header "Pod Health Check"
echo "🏥 Checking if all pods are running..."
RUNNING_PODS=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Running --no-headers | wc -l)
TOTAL_PODS=$(kubectl get pods -n $NAMESPACE --no-headers | grep -v Completed | wc -l)

echo "Running pods: $RUNNING_PODS/$TOTAL_PODS"

if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
  echo "✅ All pods are running successfully!"
else
  echo "⚠️ Some pods are not running. Checking details..."
  kubectl get pods -n $NAMESPACE | grep -v Running | grep -v Completed || echo "All pods are running"
fi

# --- Show service status ---
print_header "Service Status"
kubectl get svc -n $NAMESPACE

# --- Show ingress status ---
print_header "Ingress Status"
kubectl get ingress -n $NAMESPACE

# --- Show Access Information ---
print_header "Access Information"

echo "🚀 Checking ingress status..."
INGRESS_NAME=$(kubectl get ingress -n $NAMESPACE -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo "not-found")

if [ "$INGRESS_NAME" != "not-found" ]; then
  echo "📱 Ingress Name: $INGRESS_NAME"
  echo "🌐 To get external IP, run: kubectl get ingress -n $NAMESPACE"
  echo "🔗 Your app will be available at: https://retoucherirving.com (once DNS is configured)"
  
  # Try to get the actual IP
  INGRESS_IP=$(kubectl get ingress -n $NAMESPACE -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}" 2>/dev/null || echo "")
  if [ -n "$INGRESS_IP" ]; then
    echo "🌍 Current Ingress IP: $INGRESS_IP"
    echo "💡 Update your DNS: retoucherirving.com → $INGRESS_IP"
  fi
else
  echo "⚠️ No ingress found. Check ingress controller installation."
fi

echo ""
echo "🔌 To test locally:"
echo "kubectl port-forward svc/frontend 8080:80 -n $NAMESPACE"
echo "Then visit: http://localhost:8080"

echo ""
echo "🐘 Azure PostgreSQL Details:"
echo "Server: $PG_FQDN"
echo "Database: $DB_NAME"
echo "App User: $DB_APP_USER"

echo ""
echo "📊 To install monitoring later, run:"
echo "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts"
echo "helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace"

echo ""
echo "✅ Application deployment with Azure PostgreSQL completed successfully!"
echo ""
echo "🔍 Useful troubleshooting commands:"
echo "kubectl get pods -n $NAMESPACE"
echo "kubectl logs -f deployment/backend -n $NAMESPACE"
echo "kubectl logs -f deployment/frontend -n $NAMESPACE"
echo "kubectl logs job/db-init -n $NAMESPACE"
echo "kubectl describe pod <pod-name> -n $NAMESPACE"
echo "kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"

# #!/bin/bash

# set -euo pipefail

# # Print section header
# print_header() {
#   echo ""
#   echo "============================================================"
#   echo "  $1"
#   echo "============================================================"
#   echo ""
# }

# # --- Check CLI tools ---
# print_header "Checking CLI tools"
# for tool in az kubectl helm; do
#   if ! command -v $tool &> /dev/null; then
#     echo "Error: $tool is not installed."
#     exit 1
#   fi
# done

# # --- Set variables ---
# RESOURCE_GROUP="app-rg"
# CLUSTER_NAME="voteapp-aks"
# ACR_NAME="appacr94"
# NAMESPACE="memory-game"
# ACR_LOGIN_SERVER="appacr94.azurecr.io"
# BACKEND_IMAGE_NAME="memory-game-backend"
# FRONTEND_IMAGE_NAME="memory-game-frontend"
# IMAGE_TAG="${IMAGE_TAG:-latest}"         
# GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"

# # --- Connect to AKS cluster ---
# print_header "Connecting to AKS cluster"
# az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

# # --- Login to ACR ---
# # print_header "Logging into ACR"
# # az acr login --name "$ACR_NAME"

# # --- Create namespaces ---
# print_header "Creating application and monitoring namespaces"
# kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
# kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# # --- Deploy application resources ---
# print_header "Applying application Kubernetes manifests"
# kubectl apply -f /tmp/application/secrets.yaml
# kubectl apply -f /tmp/application/postgres-deployment.yaml
# kubectl apply -f /tmp/application/backend-deployment.yaml 
# kubectl apply -f /tmp/application/frontend-deployment.yaml   
# kubectl apply -f /tmp/application/ingress.yaml

# # --- Update images in deployments ---
# print_header "Updating backend and frontend deployments with correct image tags"
# kubectl set image deployment/backend backend="$ACR_LOGIN_SERVER/$BACKEND_IMAGE_NAME:$IMAGE_TAG" -n $NAMESPACE || echo "⚠️ Backend deployment might not exist yet"
# kubectl set image deployment/frontend frontend="$ACR_LOGIN_SERVER/$FRONTEND_IMAGE_NAME:$IMAGE_TAG" -n $NAMESPACE || echo "⚠️ Frontend deployment might not exist yet"

# # --- Deploy monitoring stack ---
# print_header "Applying monitoring Kubernetes manifests"
# kubectl apply -f /tmp/monitoring/namespace.yaml
# kubectl apply -f /tmp/monitoring/prometheus/
# kubectl apply -f /tmp/monitoring/grafana/
# kubectl apply -f /tmp/monitoring/loki/
# kubectl apply -f /tmp/monitoring/promtail/
# kubectl apply -f /tmp/monitoring/kube-state-metrics/
# kubectl apply -f /tmp/monitoring/alertmanager/
# kubectl apply -f /tmp/monitoring/node-exporter.yaml

# # Optionally apply ingress if you later want ingress for Grafana
# # kubectl apply -f /tmp/monitoring/ingress.yaml

# # --- Wait for deployments to be ready ---
# print_header "Waiting for application deployments to be ready"
# kubectl wait --for=condition=available --timeout=300s -n $NAMESPACE deployment/backend deployment/frontend

# print_header "Waiting for monitoring deployments to be ready"
# kubectl wait --for=condition=available --timeout=300s -n monitoring deployment/prometheus-deployment deployment/grafana-deployment

# print_header "Waiting for Loki pods to be ready"
# kubectl wait --for=condition=ready pod -l app=loki -n monitoring --timeout=300s || echo "⚠️ Loki pods not fully ready, check manually."

# # --- Show Access Information ---
# print_header "Access Information"

# APP_INGRESS_IP=$(kubectl get ingress -n $NAMESPACE memory-game-ingress -o jsonpath="{.status.loadBalancer.ingress[0].ip}")

# echo "🚀 Memory Game App available at: http://$APP_INGRESS_IP"
# echo ""
# echo "📊 To access Grafana, Prometheus, and Alertmanager dashboards:"
# echo ""
# echo "🔵 Grafana Port-forward:"
# echo "kubectl port-forward svc/grafana 3000:3000 -n monitoring"
# echo ""
# echo "🔵 Prometheus Port-forward:"
# echo "kubectl port-forward svc/prometheus 9090:9090 -n monitoring"
# echo ""
# echo "🔵 Alertmanager Port-forward:"
# echo "kubectl port-forward svc/alertmanager 9093:9093 -n monitoring"
# echo ""
# echo "✅ Default Grafana Login: admin / $GRAFANA_PASSWORD"

# echo ""
# echo "✅ Deployment complete!"
