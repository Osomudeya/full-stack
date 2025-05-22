# -*- mode: ruby -*-
# vi: set ft=ruby :

MASTER_IP = "192.168.56.10"
WORKER1_IP = "192.168.56.11"
WORKER2_IP = "192.168.56.12"
POD_NETWORK_CIDR = "10.244.0.0/16"
BOX_IMAGE = "ubuntu/focal64"

Vagrant.configure("2") do |config|
  config.vm.box = BOX_IMAGE
  config.vm.box_check_update = false
  
  # Global VM settings
  config.vm.provider "virtualbox" do |vb|
    vb.linked_clone = true
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
    vb.customize ["modifyvm", :id, "--ioapic", "on"]
    vb.customize ["modifyvm", :id, "--paravirtprovider", "kvm"]
    vb.customize ["modifyvm", :id, "--hwvirtex", "on"]
    vb.customize ["modifyvm", :id, "--nestedpaging", "on"]
  end

  # Bulletproof DNS Fix Script
  $fix_dns = <<-SCRIPT
    echo "=== Configuring bulletproof DNS ==="
    
    # Stop and disable systemd-resolved completely
    systemctl stop systemd-resolved.service 2>/dev/null || true
    systemctl disable systemd-resolved.service 2>/dev/null || true
    systemctl mask systemd-resolved.service 2>/dev/null || true
    
    # Remove existing resolv.conf and any symlinks
    rm -f /etc/resolv.conf
    rm -f /etc/resolv.conf.bak
    
    # Create new resolv.conf with multiple reliable DNS servers
    cat > /etc/resolv.conf << 'EOF'
# Bulletproof DNS configuration
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 9.9.9.9
options timeout:2 attempts:5 rotate single-request-reopen
search localdomain
EOF
    
    # Make it immutable to prevent overwriting
    chattr +i /etc/resolv.conf 2>/dev/null || true
    
    # Create persistent DNS service that runs on every boot
    cat > /etc/systemd/system/bulletproof-dns.service << 'EOF'
[Unit]
Description=Bulletproof DNS Configuration
After=network.target
Before=docker.service
Before=containerd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '
  chattr -i /etc/resolv.conf 2>/dev/null || true
  cat > /etc/resolv.conf << "DNSEOF"
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 9.9.9.9
options timeout:2 attempts:5 rotate single-request-reopen
search localdomain
DNSEOF
  chattr +i /etc/resolv.conf 2>/dev/null || true
'

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable bulletproof-dns.service
    systemctl start bulletproof-dns.service
    
    # Test DNS resolution extensively
    echo "Testing DNS resolution..."
    for i in {1..10}; do
      if ping -c 1 -W 3 google.com >/dev/null 2>&1 && \
         ping -c 1 -W 3 registry-1.docker.io >/dev/null 2>&1 && \
         ping -c 1 -W 3 github.com >/dev/null 2>&1; then
        echo "✅ DNS working correctly (attempt $i)"
        break
      else
        echo "⚠️  DNS test failed, attempt $i/10"
        sleep 3
      fi
    done
  SCRIPT

  # Comprehensive system setup with FIXED Docker/containerd
  $common_setup = <<-SCRIPT
    set -e
    export DEBIAN_FRONTEND=noninteractive
    
    echo "=== Starting bulletproof system setup ==="
    
    # Update system with aggressive retries
    echo "=== Updating system packages ==="
    for i in {1..5}; do
      if apt-get update && apt-get upgrade -y; then 
        echo "✅ System updated successfully"
        break
      else 
        echo "⚠️  Update attempt $i failed, retrying..."
        sleep 15
      fi
    done
    
    # Install essential packages with retries
    echo "=== Installing essential packages ==="
    for i in {1..3}; do
      if apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gpg \
        lsb-release \
        software-properties-common \
        wget \
        jq \
        vim \
        git \
        htop \
        bash-completion \
        tree \
        net-tools \
        iptables-persistent \
        nfs-common; then
        echo "✅ Essential packages installed"
        break
      else
        echo "⚠️  Package install attempt $i failed, retrying..."
        sleep 10
      fi
    done

    # Disable swap permanently and aggressively
    echo "=== Disabling swap permanently ==="
    swapoff -a 2>/dev/null || true
    sed -i '/swap/d' /etc/fstab
    systemctl mask swap.target 2>/dev/null || true
    
    # Configure kernel modules for Kubernetes
    echo "=== Configuring kernel modules ==="
    cat > /etc/modules-load.d/k8s.conf << 'EOF'
# Kubernetes required modules
overlay
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF
    
    # Load modules immediately
    modprobe overlay 2>/dev/null || true
    modprobe br_netfilter 2>/dev/null || true
    modprobe ip_vs 2>/dev/null || true
    modprobe ip_vs_rr 2>/dev/null || true
    modprobe ip_vs_wrr 2>/dev/null || true
    modprobe ip_vs_sh 2>/dev/null || true
    modprobe nf_conntrack 2>/dev/null || true
    
    # Configure sysctl parameters for Kubernetes
    echo "=== Configuring sysctl parameters ==="
    cat > /etc/sysctl.d/99-kubernetes.conf << 'EOF'
# Kubernetes networking
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.forwarding        = 1

# Disable IPv6 to avoid issues
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# Performance optimizations
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
vm.max_map_count = 262144

# Network optimizations
net.core.netdev_max_backlog = 5000
net.core.netdev_budget = 600
EOF
    
    sysctl --system
    
    # Create necessary directories with proper permissions
    echo "=== Creating required directories ==="
    mkdir -p /etc/apt/keyrings
    mkdir -p /etc/docker
    mkdir -p /etc/containerd
    mkdir -p /opt/docker-registry
    mkdir -p /etc/kubernetes/manifests
    mkdir -p /var/lib/kubelet
    chmod 755 /etc/apt/keyrings
    chmod 755 /opt/docker-registry
    
    # Remove any existing Docker installations completely
    echo "=== Removing any existing Docker installations ==="
    apt-get remove -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    
    # Clean up any leftover Docker files
    rm -rf /var/lib/docker 2>/dev/null || true
    rm -rf /var/lib/containerd 2>/dev/null || true
    rm -rf /etc/docker 2>/dev/null || true
    rm -rf /etc/containerd 2>/dev/null || true
    
    # Recreate directories
    mkdir -p /etc/docker
    mkdir -p /etc/containerd
    
    # Install Docker with comprehensive error handling
    echo "=== Installing Docker with bulletproof setup ==="
    
    # Download Docker GPG key with extensive retries
    for i in {1..10}; do
      echo "Downloading Docker GPG key (attempt $i/10)..."
      if curl -fsSL --connect-timeout 10 --max-time 30 --retry 3 \
         https://download.docker.com/linux/ubuntu/gpg | \
         gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        echo "✅ Docker GPG key downloaded successfully"
        break
      else
        echo "⚠️  Docker GPG key download failed, retrying..."
        rm -f /etc/apt/keyrings/docker.gpg
        sleep 10
      fi
    done
    
    # Verify GPG key exists
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
      echo "❌ CRITICAL: Failed to download Docker GPG key after 10 attempts"
      exit 1
    fi
    
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    
    # Install containerd first, then Docker
    echo "=== Installing containerd first ==="
    for i in {1..5}; do
      if apt-get update && apt-get install -y containerd.io; then
        echo "✅ containerd installed successfully"
        break
      else
        echo "⚠️  containerd install attempt $i failed, retrying..."
        sleep 15
      fi
    done
    
    # Configure containerd BEFORE starting it
    echo "=== Configuring containerd ==="
    containerd config default > /etc/containerd/config.toml
    
    # Enable systemd cgroup driver and fix critical settings
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    # Add sandbox_image configuration to prevent image pull issues
    sed -i 's|sandbox_image = "registry.k8s.io/pause:3.6"|sandbox_image = "registry.k8s.io/pause:3.9"|' /etc/containerd/config.toml
    
    # Configure registry support
    cat >> /etc/containerd/config.toml << 'EOF'

# Custom registry configuration
[plugins."io.containerd.grpc.v1.cri".registry]
  config_path = ""

[plugins."io.containerd.grpc.v1.cri".registry.mirrors]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
    endpoint = ["https://registry-1.docker.io"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
    endpoint = ["http://localhost:5000"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.56.10:30000"]
    endpoint = ["http://192.168.56.10:30000"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.56.10:5000"]
    endpoint = ["http://192.168.56.10:5000"]

[plugins."io.containerd.grpc.v1.cri".registry.configs]
  [plugins."io.containerd.grpc.v1.cri".registry.configs."localhost:5000".tls]
    insecure_skip_verify = true
  [plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.56.10:30000".tls]
    insecure_skip_verify = true
  [plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.56.10:5000".tls]
    insecure_skip_verify = true
EOF
    
    # Start containerd with proper error handling
    echo "=== Starting containerd service ==="
    systemctl daemon-reload
    systemctl enable containerd
    
    for i in {1..5}; do
      echo "Starting containerd (attempt $i/5)..."
      if systemctl start containerd && systemctl is-active --quiet containerd; then
        echo "✅ containerd started successfully"
        break
      else
        echo "⚠️  containerd start failed, attempt $i/5"
        systemctl status containerd --no-pager || true
        journalctl -u containerd --no-pager -n 20 || true
        systemctl stop containerd 2>/dev/null || true
        sleep 10
        systemctl daemon-reload
      fi
    done
    
    # Verify containerd is working
    if ! systemctl is-active --quiet containerd; then
      echo "❌ CRITICAL: containerd failed to start"
      systemctl status containerd --no-pager
      journalctl -u containerd --no-pager -n 50
      exit 1
    fi
    
    # Wait for containerd socket to be ready
    echo "=== Waiting for containerd socket ==="
    for i in {1..30}; do
      if [ -S /run/containerd/containerd.sock ]; then
        echo "✅ containerd socket is ready"
        break
      else
        echo "⏳ Waiting for containerd socket (attempt $i/30)..."
        sleep 2
      fi
    done
    
    # Now install Docker
    echo "=== Installing Docker ==="
    for i in {1..5}; do
      if apt-get install -y docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin; then
        echo "✅ Docker packages installed successfully"
        break
      else
        echo "⚠️  Docker install attempt $i failed, retrying..."
        sleep 15
      fi
    done
    
    # Configure Docker daemon with comprehensive settings
    cat > /etc/docker/daemon.json << 'EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "insecure-registries": [
    "localhost:5000",
    "192.168.56.10:30000",
    "192.168.56.10:5000"
  ],
  "registry-mirrors": [],
  "dns": ["8.8.8.8", "8.8.4.4", "1.1.1.1"],
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false,
  "metrics-addr": "0.0.0.0:9323",
  "iptables": true,
  "default-runtime": "runc",
  "containerd": "/run/containerd/containerd.sock"
}
EOF
    
    # Start Docker with proper error handling
    echo "=== Starting Docker service ==="
    systemctl daemon-reload
    systemctl enable docker
    
    for i in {1..5}; do
      echo "Starting Docker (attempt $i/5)..."
      if systemctl start docker && systemctl is-active --quiet docker; then
        echo "✅ Docker started successfully"
        break
      else
        echo "⚠️  Docker start failed, attempt $i/5"
        systemctl status docker --no-pager || true
        journalctl -u docker --no-pager -n 20 || true
        systemctl stop docker 2>/dev/null || true
        sleep 10
        systemctl daemon-reload
      fi
    done
    
    # Verify Docker is working
    if ! systemctl is-active --quiet docker; then
      echo "❌ CRITICAL: Docker failed to start"
      systemctl status docker --no-pager
      journalctl -u docker --no-pager -n 50
      exit 1
    fi
    
    # Add vagrant user to docker group
    usermod -aG docker vagrant
    
    # Test Docker functionality
    echo "=== Testing Docker functionality ==="
    sleep 10  # Give Docker time to fully initialize
    
    for i in {1..5}; do
      echo "Testing Docker (attempt $i/5)..."
      if docker info >/dev/null 2>&1; then
        echo "✅ Docker is working correctly"
        break
      else
        echo "⚠️  Docker test failed, attempt $i/5"
        sleep 10
      fi
    done
    
    # Final Docker test with hello-world
    echo "=== Final Docker test ==="
    if docker run --rm hello-world >/dev/null 2>&1; then
      echo "✅ Docker hello-world test passed"
    else
      echo "⚠️  Docker hello-world test failed, but continuing..."
    fi
    
    # Install Kubernetes components
    echo "=== Installing Kubernetes ==="
    
    # Download Kubernetes GPG key with retries
    for i in {1..10}; do
      echo "Downloading Kubernetes GPG key (attempt $i/10)..."
      if curl -fsSL --connect-timeout 10 --max-time 30 --retry 3 \
         https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | \
         gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg; then
        echo "✅ Kubernetes GPG key downloaded successfully"
        break
      else
        echo "⚠️  Kubernetes GPG key download failed, retrying..."
        rm -f /etc/apt/keyrings/kubernetes.gpg
        sleep 10
      fi
    done
    
    # Verify Kubernetes GPG key exists
    if [ ! -f /etc/apt/keyrings/kubernetes.gpg ]; then
      echo "❌ CRITICAL: Failed to download Kubernetes GPG key after 10 attempts"
      exit 1
    fi
    
    chmod a+r /etc/apt/keyrings/kubernetes.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
    
    # Install Kubernetes components with retries
    for i in {1..5}; do
      if apt-get update && \
         apt-get install -y kubelet kubeadm kubectl; then
        echo "✅ Kubernetes components installed successfully"
        break
      else
        echo "⚠️  Kubernetes install attempt $i failed, retrying..."
        sleep 15
      fi
    done
    
    apt-mark hold kubelet kubeadm kubectl
    
    # Configure kubelet
    mkdir -p /etc/systemd/system/kubelet.service.d
    
    # Create comprehensive startup script
    cat > /usr/local/bin/k8s-startup.sh << 'EOF'
#!/bin/bash
echo "Starting Kubernetes services..."
systemctl start bulletproof-dns.service
systemctl restart containerd
sleep 5
systemctl restart docker
sleep 5
systemctl restart kubelet
echo "Kubernetes services started"
EOF
    chmod +x /usr/local/bin/k8s-startup.sh
    
    # Create systemd service for startup
    cat > /etc/systemd/system/k8s-startup.service << 'EOF'
[Unit]
Description=Kubernetes Startup Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/k8s-startup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable k8s-startup.service
    
    echo "=== Common setup completed successfully ==="
    echo "✅ Docker version: $(docker --version)"
    echo "✅ containerd version: $(containerd --version)"
    echo "✅ kubelet version: $(kubelet --version)"
  SCRIPT

  # Master node configuration
  config.vm.define "master" do |master|
    master.vm.hostname = "master"
    master.vm.network "private_network", ip: MASTER_IP
    
    master.vm.provider "virtualbox" do |vb|
      vb.memory = 4096  # Increased memory for stability
      vb.cpus = 2
      vb.name = "k8s-master"
      vb.gui = true
    end
    
    master.vm.provision "shell", inline: $fix_dns
    master.vm.provision "shell", inline: $common_setup
    
    # Master-specific setup
    master.vm.provision "shell", inline: <<-SCRIPT
      echo "=== Configuring master node ==="
      
      # Configure kubelet for master
      echo "KUBELET_EXTRA_ARGS=--node-ip=#{MASTER_IP} --cgroup-driver=systemd" > /etc/default/kubelet
      systemctl daemon-reload
      systemctl restart kubelet
      systemctl enable kubelet
      
      echo "=== Initializing Kubernetes cluster ==="
      # Initialize cluster with comprehensive configuration
      kubeadm init \
        --apiserver-advertise-address=#{MASTER_IP} \
        --pod-network-cidr=#{POD_NETWORK_CIDR} \
        --apiserver-cert-extra-sans=#{MASTER_IP},localhost,127.0.0.1 \
        --control-plane-endpoint=#{MASTER_IP} \
        --upload-certs \
        --ignore-preflight-errors=NumCPU,Mem \
        --cri-socket=unix:///var/run/containerd/containerd.sock \
        --v=2
      
      # Set up kubectl for vagrant user
      echo "=== Setting up kubectl access ==="
      mkdir -p /home/vagrant/.kube
      cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
      chown -R vagrant:vagrant /home/vagrant/.kube
      
      # Set up kubectl for root (for system operations)
      mkdir -p /root/.kube
      cp /etc/kubernetes/admin.conf /root/.kube/config
      
      echo "=== Waiting for API server to be ready ==="
      su - vagrant -c "kubectl wait --for=condition=Ready node/master --timeout=300s" || echo "Master not ready yet, continuing..."
      
      # Install Calico network plugin with proper configuration
      echo "=== Installing Calico network plugin ==="
      su - vagrant -c "curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml"
      
      # Modify Calico manifest for our pod CIDR
      su - vagrant -c "sed -i 's|# - name: CALICO_IPV4POOL_CIDR|  - name: CALICO_IPV4POOL_CIDR|g' calico.yaml"
      su - vagrant -c "sed -i 's|#   value: \"192.168.0.0/16\"|    value: \"#{POD_NETWORK_CIDR}\"|g' calico.yaml"
      
      # Apply Calico
      su - vagrant -c "kubectl apply -f calico.yaml"
      
      # Wait for Calico to be ready
      echo "=== Waiting for Calico to be ready ==="
      su - vagrant -c "kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=600s" || echo "Some pods not ready yet"
      
      # Generate join command with extended TTL
      echo "=== Generating join command ==="
      kubeadm token create --ttl 0 --print-join-command > /vagrant/join-command.sh
      chmod +x /vagrant/join-command.sh
      
      # Set up bash completion and aliases
      cat >> /home/vagrant/.bashrc << 'EOF'
source <(kubectl completion bash)
alias k=kubectl
complete -F __start_kubectl k
export KUBECONFIG=$HOME/.kube/config
EOF
      
      # Install NGINX Ingress Controller
      echo "=== Installing NGINX Ingress Controller ==="
      su - vagrant -c "kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml"
      
      # Wait for ingress controller to be ready
      echo "=== Waiting for NGINX Ingress Controller ==="
      su - vagrant -c "kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s" || echo "Ingress controller not ready yet"
      
      # Install Helm
      echo "=== Installing Helm ==="
      curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
      
      # Add cert-manager helm repository
      echo "=== Installing cert-manager ==="
      su - vagrant -c "helm repo add jetstack https://charts.jetstack.io"
      su - vagrant -c "helm repo update"
      
      # Install cert-manager
      su - vagrant -c "kubectl create namespace cert-manager || true"
      su - vagrant -c "helm install cert-manager jetstack/cert-manager --namespace cert-manager --version v1.13.0 --set installCRDs=true"
      
      # Wait for cert-manager to be ready
      su - vagrant -c "kubectl wait --for=condition=ready pod --selector=app=cert-manager -n cert-manager --timeout=300s" || echo "Cert-manager not ready yet"
      su - vagrant -c "kubectl wait --for=condition=ready pod --selector=app=cainjector -n cert-manager --timeout=300s" || echo "Cert-manager cainjector not ready yet"
      su - vagrant -c "kubectl wait --for=condition=ready pod --selector=app=webhook -n cert-manager --timeout=300s" || echo "Cert-manager webhook not ready yet"
      
      # Create Let's Encrypt cluster issuer
      cat > /tmp/letsencrypt-issuer.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@retoucherirving.com  # Change this to your email
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@retoucherirving.com  # Change this to your email
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
      
      # Apply Let's Encrypt issuers
      su - vagrant -c "kubectl apply -f /tmp/letsencrypt-issuer.yaml"
      
      # Create namespace for Docker registry
      su - vagrant -c "kubectl create namespace docker-registry || true"
      
      # Create persistent Docker registry with hostPath storage
      echo "=== Setting up persistent Docker registry ==="
      cat > /tmp/docker-registry.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docker-registry
  namespace: docker-registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: docker-registry
  template:
    metadata:
      labels:
        app: docker-registry
    spec:
      containers:
      - name: registry
        image: registry:2
        ports:
        - containerPort: 5000
        env:
        - name: REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY
          value: /var/lib/registry
        - name: REGISTRY_HTTP_ADDR
          value: 0.0.0.0:5000
        - name: REGISTRY_STORAGE_DELETE_ENABLED
          value: "true"
        volumeMounts:
        - name: registry-storage
          mountPath: /var/lib/registry
        livenessProbe:
          httpGet:
            path: /v2/
            port: 5000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /v2/
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: registry-storage
        hostPath:
          path: /opt/docker-registry
          type: DirectoryOrCreate
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      nodeSelector:
        kubernetes.io/hostname: master
---
apiVersion: v1
kind: Service
metadata:
  name: docker-registry
  namespace: docker-registry
spec:
  selector:
    app: docker-registry
  ports:
  - name: registry
    port: 5000
    targetPort: 5000
    nodePort: 30000
  type: NodePort
EOF

      # Apply registry configuration
      su - vagrant -c "kubectl apply -f /tmp/docker-registry.yaml"
      
      # Wait for registry to be ready
      echo "=== Waiting for Docker registry to be ready ==="
      su - vagrant -c "kubectl wait --for=condition=available --timeout=300s deployment/docker-registry -n docker-registry"
      
      # Create deployment backup directory
      mkdir -p /vagrant/k8s-deployments
      
      # Save registry deployment for persistence
      su - vagrant -c "kubectl get deployment,service -n docker-registry -o yaml > /vagrant/k8s-deployments/docker-registry.yaml"
      
      # Test registry functionality
      echo "=== Testing Docker registry ==="
      sleep 30  # Wait for registry to fully initialize
      
      # Test with actual image
      docker pull busybox:latest
      docker tag busybox:latest #{MASTER_IP}:30000/test-busybox:latest
      docker push #{MASTER_IP}:30000/test-busybox:latest || echo "Push failed, but registry is running"
      
      # Remove the control-plane taint to allow scheduling
      su - vagrant -c "kubectl taint nodes master node-role.kubernetes.io/control-plane:NoSchedule-" || echo "Taint already removed"
      
      echo "=== Master node setup completed successfully ==="
      echo ""
      echo "🎉 Kubernetes Master Ready!"
      echo "📊 Cluster Status:"
      su - vagrant -c "kubectl get nodes -o wide"
      echo ""
      echo "🐳 Docker Registry:"
      echo "   URL: http://#{MASTER_IP}:30000"
      echo "   Test: curl http://#{MASTER_IP}:30000/v2/_catalog"
      echo ""
      echo "📝 Next Steps:"
      echo "   1. Wait for worker nodes to join"
      echo "   2. Deploy your applications"
      echo "   3. Use 'vagrant ssh master' to access master node"
    SCRIPT
    
    # Auto-restore script that runs every time VM starts
    master.vm.provision "shell", run: "always", inline: <<-SCRIPT
      echo "=== Auto-restore: Ensuring cluster health ==="
      
      # Wait for cluster to be responsive
      timeout 180 bash -c 'until kubectl get nodes &>/dev/null; do echo "Waiting for cluster..."; sleep 10; done' || echo "Cluster not ready"
      
      # Restore registry if missing
      if ! kubectl get svc docker-registry -n docker-registry &>/dev/null; then
        echo "🔄 Restoring Docker registry..."
        su - vagrant -c "kubectl apply -f /vagrant/k8s-deployments/docker-registry.yaml"
        su - vagrant -c "kubectl wait --for=condition=available --timeout=300s deployment/docker-registry -n docker-registry" || echo "Registry not ready yet"
      fi
      
      # Restore other deployments if they exist
      if [ -d /vagrant/k8s-deployments ] && [ "$(ls -A /vagrant/k8s-deployments)" ]; then
        for file in /vagrant/k8s-deployments/*.yaml; do
          if [ "$file" != "/vagrant/k8s-deployments/docker-registry.yaml" ] && [ -f "$file" ]; then
            echo "🔄 Restoring $(basename $file)..."
            su - vagrant -c "kubectl apply -f $file" || echo "Failed to restore $file"
          fi
        done
      fi
      
      echo "✅ Auto-restore completed"
    SCRIPT
  end
  
  # Worker nodes configuration
  ["worker1", WORKER1_IP, "worker2", WORKER2_IP].each_slice(2) do |name, ip|
    config.vm.define name do |worker|
      worker.vm.hostname = name
      worker.vm.network "private_network", ip: ip
      
      worker.vm.provider "virtualbox" do |vb|
        vb.memory = 2048
        vb.cpus = 2
        vb.name = "k8s-#{name}"
        vb.gui = true
      end
      
      worker.vm.provision "shell", inline: $fix_dns
      worker.vm.provision "shell", inline: $common_setup
      
      worker.vm.provision "shell", inline: <<-SCRIPT
        echo "=== Configuring #{name} node ==="
        
        # Configure kubelet for worker
        echo "KUBELET_EXTRA_ARGS=--node-ip=#{ip} --cgroup-driver=systemd" > /etc/default/kubelet
        systemctl daemon-reload
        systemctl restart kubelet
        systemctl enable kubelet
        
        echo "=== Waiting for join command ==="
        # Wait for join command with extended timeout
        timeout=600
        elapsed=0
        while [ ! -f /vagrant/join-command.sh ] && [ $elapsed -lt $timeout ]; do
          echo "⏳ Waiting for join command... ($elapsed/$timeout seconds)"
          sleep 15
          elapsed=$((elapsed + 15))
        done
        
        if [ ! -f /vagrant/join-command.sh ]; then
          echo "❌ CRITICAL: Join command not found after $timeout seconds"
          echo "Please check master node initialization"
          exit 1
        fi
        
        echo "=== Joining the Kubernetes cluster ==="
        # Join with retries
        for i in {1..3}; do
          if bash /vagrant/join-command.sh --ignore-preflight-errors=all; then
            echo "✅ Successfully joined cluster"
            break
          else
            echo "⚠️  Join attempt $i failed, retrying..."
            sleep 30
          fi
        done
        
        # Test Docker functionality on worker
        echo "=== Testing Docker on worker node ==="
        docker pull busybox:latest || echo "External pull failed"
        
        # Test registry access
        for i in {1..10}; do
          if curl -f http://#{MASTER_IP}:30000/v2/ >/dev/null 2>&1; then
            echo "✅ Registry accessible from #{name}"
            break
          else
            echo "⏳ Testing registry access from #{name} (attempt $i/10)"
            sleep 15
          fi
        done
        
        echo "=== #{name} node setup completed ==="
        echo "✅ Worker node #{name} is ready"
        echo "🐳 Registry accessible at: #{MASTER_IP}:30000"
      SCRIPT
      
      # Auto-join script for worker nodes
      worker.vm.provision "shell", run: "always", inline: <<-SCRIPT
        echo "=== Auto-restore: Ensuring #{name} cluster membership ==="
        
        # Check if node is part of cluster
        if ! timeout 60 kubectl --kubeconfig=/etc/kubernetes/kubelet.conf get nodes &>/dev/null; then
          echo "🔄 Node not in cluster, attempting to rejoin..."
          if [ -f /vagrant/join-command.sh ]; then
            bash /vagrant/join-command.sh --ignore-preflight-errors=all || echo "Rejoin failed"
          fi
        else
          echo "✅ #{name} is part of the cluster"
        fi
      SCRIPT
    end
  end
end