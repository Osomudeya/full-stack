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
  end

  # DNS Fix Script - Bulletproof DNS configuration
  $fix_dns = <<-SCRIPT
    echo "=== Configuring reliable DNS ==="
    
    # Stop and disable systemd-resolved
    systemctl stop systemd-resolved.service || true
    systemctl disable systemd-resolved.service || true
    
    # Remove existing resolv.conf
    rm -f /etc/resolv.conf
    
    # Create new resolv.conf with multiple DNS servers
    cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 9.9.9.9
options timeout:2 attempts:3 rotate single-request-reopen
EOF
    
    # Make it immutable to prevent overwriting
    chattr +i /etc/resolv.conf || true
    
    # Create persistent DNS service
    cat > /etc/systemd/system/persistent-dns.service << EOF
[Unit]
Description=Persistent DNS Configuration
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'chattr -i /etc/resolv.conf; echo "nameserver 8.8.8.8" > /etc/resolv.conf; echo "nameserver 8.8.4.4" >> /etc/resolv.conf; echo "nameserver 1.1.1.1" >> /etc/resolv.conf; echo "options timeout:2 attempts:3 rotate single-request-reopen" >> /etc/resolv.conf; chattr +i /etc/resolv.conf'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable persistent-dns.service
    systemctl start persistent-dns.service
    
    # Test DNS resolution for both external and Docker Hub
    echo "Testing DNS resolution..."
    for i in {1..5}; do
      if ping -c 1 -W 2 google.com >/dev/null 2>&1 && ping -c 1 -W 2 registry-1.docker.io >/dev/null 2>&1; then
        echo "DNS working correctly for external and Docker Hub"
        break
      else
        echo "DNS test failed, attempt $i/5"
        sleep 2
      fi
    done
  SCRIPT

  # Common setup for all nodes
  $common_setup = <<-SCRIPT
    set -e
    export DEBIAN_FRONTEND=noninteractive
    
    echo "=== Starting system setup ==="
    
    # Update system with retries
    for i in {1..3}; do
      if apt-get update; then break; else echo "Update attempt $i failed, retrying..."; sleep 10; fi
    done
    
    # Install essential packages first
    echo "=== Installing essential packages ==="
    apt-get install -y apt-transport-https ca-certificates curl gpg lsb-release software-properties-common wget

    # Disable swap permanently
    echo "=== Disabling swap ==="
    swapoff -a
    sed -i '/swap/d' /etc/fstab
    
    # Configure kernel modules
    echo "=== Configuring kernel modules ==="
    cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    
    modprobe overlay
    modprobe br_netfilter
    
    # Configure sysctl parameters
    echo "=== Configuring sysctl parameters ==="
    cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
    sysctl --system
    
    # Create necessary directories FIRST
    echo "=== Creating required directories ==="
    mkdir -p /etc/apt/keyrings
    mkdir -p /etc/docker
    mkdir -p /etc/containerd
    chmod 755 /etc/apt/keyrings
    
    # Install Docker with proper error handling
    echo "=== Installing Docker ==="
    # Download Docker GPG key with retries
    for i in {1..5}; do
      echo "Attempting to download Docker GPG key (attempt $i/5)..."
      if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        echo "Docker GPG key downloaded successfully"
        break
      else
        echo "Failed to download Docker GPG key, retrying..."
        rm -f /etc/apt/keyrings/docker.gpg
        sleep 10
      fi
    done
    
    # Verify GPG key was created
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
      echo "ERROR: Failed to create Docker GPG key after 5 attempts"
      exit 1
    fi
    
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    
    # Update package lists and install Docker
    for i in {1..3}; do
      if apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        echo "Docker installed successfully"
        break
      else
        echo "Docker install attempt $i failed, retrying..."
        sleep 10
      fi
    done
    
    # Configure Docker daemon
    cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "insecure-registries": ["localhost:5000", "192.168.56.10:30000"],
  "registry-mirrors": [],
  "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF
    
    # Configure containerd for both local and external registries
    echo "=== Configuring containerd ==="
    containerd config default > /etc/containerd/config.toml
    
    # Enable systemd cgroup driver
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    # Configure registry support for both local and external
    cat >> /etc/containerd/config.toml <<EOF

# Custom registry configuration for local registry
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
  endpoint = ["http://localhost:5000"]

[plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.56.10:30000"]
  endpoint = ["http://192.168.56.10:30000"]

# Ensure Docker Hub works properly
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
  endpoint = ["https://registry-1.docker.io"]

# Configure insecure registries
[plugins."io.containerd.grpc.v1.cri".registry.configs."localhost:5000".tls]
  insecure_skip_verify = true

[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.56.10:30000".tls]
  insecure_skip_verify = true
EOF
    
    # Start and enable services
    systemctl daemon-reload
    systemctl restart containerd
    systemctl enable containerd
    systemctl restart docker
    systemctl enable docker
    
    # Add vagrant user to docker group
    usermod -aG docker vagrant
    
    # Install Kubernetes components
    echo "=== Installing Kubernetes ==="
    
    # Download Kubernetes GPG key with retries
    for i in {1..5}; do
      echo "Attempting to download Kubernetes GPG key (attempt $i/5)..."
      if curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg; then
        echo "Kubernetes GPG key downloaded successfully"
        break
      else
        echo "Failed to download Kubernetes GPG key, retrying..."
        rm -f /etc/apt/keyrings/kubernetes.gpg
        sleep 10
      fi
    done
    
    # Verify Kubernetes GPG key was created
    if [ ! -f /etc/apt/keyrings/kubernetes.gpg ]; then
      echo "ERROR: Failed to create Kubernetes GPG key after 5 attempts"
      exit 1
    fi
    
    chmod a+r /etc/apt/keyrings/kubernetes.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
    
    # Install Kubernetes components with retries
    for i in {1..3}; do
      if apt-get update && apt-get install -y kubelet kubeadm kubectl; then
        echo "Kubernetes components installed successfully"
        break
      else
        echo "Kubernetes install attempt $i failed, retrying..."
        sleep 10
      fi
    done
    
    apt-mark hold kubelet kubeadm kubectl
    
    # Install useful tools
    apt-get install -y jq vim git htop bash-completion tree net-tools
    
    # Test external Docker image pull capability
    echo "=== Testing external Docker image pull ==="
    docker pull hello-world || echo "Warning: Could not pull external Docker image"
    
    # Create startup script for post-reboot services
    cat > /usr/local/bin/k8s-startup.sh <<EOF
#!/bin/bash
systemctl start persistent-dns.service
systemctl restart containerd
systemctl restart docker
systemctl restart kubelet
EOF
    chmod +x /usr/local/bin/k8s-startup.sh
    
    # Add to rc.local for startup
    cat > /etc/rc.local <<EOF
#!/bin/bash
/usr/local/bin/k8s-startup.sh
exit 0
EOF
    chmod +x /etc/rc.local
    
    echo "=== Common setup completed successfully ==="
  SCRIPT

  # Master node configuration
  config.vm.define "master" do |master|
    master.vm.hostname = "master"
    master.vm.network "private_network", ip: MASTER_IP
    
    master.vm.provider "virtualbox" do |vb|
      vb.memory = 3072
      vb.cpus = 2
      vb.name = "k8s-master"
      vb.gui = true
    end
    
    master.vm.provision "shell", inline: $fix_dns
    master.vm.provision "shell", inline: $common_setup
    
    master.vm.provision "shell", inline: <<-SCRIPT
      echo "=== Configuring master node ==="
      
      # Configure kubelet
      echo "KUBELET_EXTRA_ARGS=--node-ip=#{MASTER_IP}" > /etc/default/kubelet
      systemctl daemon-reload
      systemctl restart kubelet
      systemctl enable kubelet
      
      echo "=== Initializing Kubernetes cluster ==="
      # Initialize cluster with proper configuration
      kubeadm init \
        --apiserver-advertise-address=#{MASTER_IP} \
        --pod-network-cidr=#{POD_NETWORK_CIDR} \
        --apiserver-cert-extra-sans=#{MASTER_IP} \
        --ignore-preflight-errors=NumCPU,Mem \
        --upload-certs
      
      # Set up kubectl for vagrant user
      echo "=== Setting up kubectl ==="
      mkdir -p /home/vagrant/.kube
      cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
      chown -R vagrant:vagrant /home/vagrant/.kube
      
      # Install Calico network plugin
      echo "=== Installing Calico network plugin ==="
      su - vagrant -c "kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml"
      
      # Wait for control plane to be ready
      echo "=== Waiting for control plane ==="
      su - vagrant -c "kubectl wait --for=condition=Ready node/master --timeout=300s"
      
      # Generate join command with longer TTL
      echo "=== Generating join command ==="
      kubeadm token create --ttl 24h --print-join-command > /vagrant/join-command.sh
      chmod +x /vagrant/join-command.sh
      
      # Set up bash completion and aliases
      echo 'source <(kubectl completion bash)' >> /home/vagrant/.bashrc
      echo 'alias k=kubectl' >> /home/vagrant/.bashrc
      echo 'complete -F __start_kubectl k' >> /home/vagrant/.bashrc
      
      # Install NGINX Ingress Controller
      echo "=== Installing NGINX Ingress Controller ==="
      su - vagrant -c "kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml"
      
      # Install Helm
      echo "=== Installing Helm ==="
      curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
      
      # Set up local Docker registry
      echo "=== Setting up local Docker registry ==="
      su - vagrant -c "kubectl create namespace docker-registry"
      
      cat <<EOF | su - vagrant -c "kubectl apply -f -"
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
        volumeMounts:
        - name: registry-storage
          mountPath: /var/lib/registry
      volumes:
      - name: registry-storage
        emptyDir: {}
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
  - port: 5000
    targetPort: 5000
    nodePort: 30000
  type: NodePort
EOF

      # Wait for registry to be ready
      su - vagrant -c "kubectl wait --for=condition=available --timeout=300s deployment/docker-registry -n docker-registry"
      
      # Test both external and local registry functionality
      echo "=== Testing Docker registry functionality ==="
      
      # Test external pull
      echo "Testing external Docker pull..."
      docker pull nginx:alpine || echo "Warning: External pull failed"
      
      # Test local registry
      echo "Testing local registry..."
      docker tag nginx:alpine 192.168.56.10:30000/test-nginx:latest || echo "Warning: Could not tag for local registry"
      docker push 192.168.56.10:30000/test-nginx:latest || echo "Warning: Could not push to local registry"
      
      echo "=== Master node setup completed ==="
      su - vagrant -c "kubectl get nodes"
      echo "Local registry available at: #{MASTER_IP}:30000"
      echo "External Docker Hub pulls: ENABLED"
      echo ""
      echo "Usage examples:"
      echo "  External pull: docker pull nginx:latest"
      echo "  Local push:    docker tag nginx:latest #{MASTER_IP}:30000/nginx:latest && docker push #{MASTER_IP}:30000/nginx:latest"
      echo "  K8s local:     image: #{MASTER_IP}:30000/nginx:latest"
      echo "  K8s external:  image: nginx:latest"
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
        
        # Configure kubelet
        echo "KUBELET_EXTRA_ARGS=--node-ip=#{ip}" > /etc/default/kubelet
        systemctl daemon-reload
        systemctl restart kubelet
        systemctl enable kubelet
        
        echo "=== Waiting for join command ==="
        # Wait for join command to be available with timeout
        timeout=300
        elapsed=0
        while [ ! -f /vagrant/join-command.sh ] && [ $elapsed -lt $timeout ]; do
          echo "Waiting for join command... ($elapsed/$timeout seconds)"
          sleep 10
          elapsed=$((elapsed + 10))
        done
        
        if [ ! -f /vagrant/join-command.sh ]; then
          echo "ERROR: Join command not found after $timeout seconds"
          exit 1
        fi
        
        echo "=== Joining the cluster ==="
        bash /vagrant/join-command.sh --ignore-preflight-errors=all
        
        # Test external Docker pull on worker node
        echo "=== Testing external Docker pull on worker ==="
        docker pull busybox:latest || echo "Warning: Could not pull external image on worker"
        
        echo "=== #{name} node setup completed ==="
        echo "External Docker Hub pulls: ENABLED"
        echo "Local registry access: #{MASTER_IP}:30000"
      SCRIPT
    end
  end
end