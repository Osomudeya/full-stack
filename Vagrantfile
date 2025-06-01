# -*- mode: ruby -*-
# vi: set ft=ruby :

# Configuration
MASTER_IP = "192.168.56.10"
WORKER1_IP = "192.168.56.11" 
WORKER2_IP = "192.168.56.12"
POD_NETWORK_CIDR = "10.244.0.0/16"
BOX_IMAGE = "ubuntu/focal64"
K8S_VERSION = "1.28"

Vagrant.configure("2") do |config|
  config.vm.box = BOX_IMAGE
  config.vm.box_check_update = false
  
  # IMPROVED: Better VirtualBox networking settings
  config.vm.provider "virtualbox" do |vb|
    vb.linked_clone = true
    # Enhanced networking for Kubernetes
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"] 
    vb.customize ["modifyvm", :id, "--ioapic", "on"]
    # CRITICAL: Enable promiscuous mode for better networking
    vb.customize ["modifyvm", :id, "--nicpromisc2", "allow-all"]
    # Increase network performance
    vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
    vb.customize ["modifyvm", :id, "--nictype2", "virtio"]
  end

  # IMPROVED: Enhanced DNS fix script
  $fix_dns = <<-'SCRIPT'
    echo "=== Configuring DNS ==="
    
    # Completely disable systemd-resolved to prevent conflicts
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true
    systemctl mask systemd-resolved 2>/dev/null || true
    
    # Remove any symlinks
    rm -f /etc/resolv.conf
    
    # Create static resolv.conf
    cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4  
nameserver 1.1.1.1
search localdomain
options timeout:2 attempts:3 rotate
EOF
    
    # Make it immutable to prevent overwrites
    chattr +i /etc/resolv.conf 2>/dev/null || true
    
    # Test DNS
    echo "Testing DNS resolution..."
    if nslookup google.com >/dev/null 2>&1; then
      echo "✅ DNS working"
    else
      echo "⚠️ DNS test failed but continuing..."
    fi
  SCRIPT

  # IMPROVED: Network optimization script
  $optimize_network = <<-'SCRIPT'
    echo "=== Optimizing Network for Kubernetes ==="
    
    # Increase network buffers for better performance
    cat >> /etc/sysctl.d/99-kubernetes.conf << 'EOF'
# Network optimizations for Kubernetes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 5000
net.ipv4.neigh.default.gc_thresh1 = 4096
net.ipv4.neigh.default.gc_thresh2 = 8192
net.ipv4.neigh.default.gc_thresh3 = 16384
EOF
    
    sysctl --system
    
    # Ensure proper interface naming
    if ! grep -q "net.ifnames=0" /etc/default/grub; then
      sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="net.ifnames=0"/' /etc/default/grub
      update-grub || true
    fi
    
    echo "✅ Network optimization completed"
  SCRIPT

  # Common setup for all nodes (keeping your existing script but with improvements)
  $common_setup = <<-'SCRIPT'
    export DEBIAN_FRONTEND=noninteractive
    
    echo "=== System Setup ==="
    
    # Update system with better error handling
    echo "=== Updating package lists ==="
    apt-get update
    
    echo "=== Upgrading system packages (non-critical) ==="
    apt-get upgrade -y || echo "⚠️ Some packages failed to upgrade, continuing..."
    
    # Install essential packages
    echo "=== Installing essential packages ==="
    apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      gpg \
      software-properties-common \
      wget \
      vim \
      htop \
      net-tools \
      dnsutils || {
      echo "❌ Failed to install essential packages"
      exit 1
    }
    
    set -e
    
    # Disable swap
    echo "=== Disabling swap ==="
    swapoff -a
    sed -i '/swap/d' /etc/fstab
    
    # Load kernel modules
    cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF
    
    modprobe overlay
    modprobe br_netfilter
    
    # IMPROVED: Enhanced sysctl configuration
    cat > /etc/sysctl.d/99-kubernetes.conf << 'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
# Additional networking optimizations
net.ipv4.conf.all.forwarding = 1
net.ipv6.conf.all.forwarding = 1
net.netfilter.nf_conntrack_max = 131072
EOF
    
    sysctl --system
    
    # Install Docker (keeping your existing Docker installation)
    echo "=== Installing Docker ==="
    mkdir -p /etc/apt/keyrings
    apt-get autoremove -y || true
    apt-get autoclean || true
    
    for i in {1..3}; do
      if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "✅ Docker GPG key added successfully"
        break
      else
        echo "⚠️ Docker GPG key attempt $i failed, retrying..."
        sleep 5
        if [ $i -eq 3 ]; then
          echo "❌ Failed to add Docker GPG key after 3 attempts"
          exit 1
        fi
      fi
    done
    
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    
    echo "✅ Docker packages installed"
    
    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    sed -i 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.9"|' /etc/containerd/config.toml
    
    # Configure Docker
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file", 
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
    
    # Start services
    systemctl daemon-reload
    systemctl enable containerd docker
    systemctl restart containerd
    systemctl restart docker
    
    sleep 10
    
    if ! systemctl is-active --quiet docker; then
      echo "❌ Docker failed to start"
      systemctl status docker --no-pager
      exit 1
    fi
    
    if ! systemctl is-active --quiet containerd; then
      echo "❌ Containerd failed to start"
      systemctl status containerd --no-pager
      exit 1
    fi
    
    echo "✅ Docker and containerd are running"
    
    # Test Docker functionality
    if timeout 30 docker run --rm hello-world >/dev/null 2>&1; then
      echo "✅ Docker test passed"
    else
      echo "⚠️ Docker test failed, but continuing..."
    fi
    
    usermod -aG docker vagrant
    
    # Install Kubernetes (keeping your existing installation)
    echo "=== Installing Kubernetes ==="
    mkdir -p /etc/apt/keyrings
    
    for i in {1..3}; do
      if curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg; then
        echo "✅ Kubernetes GPG key added successfully"
        break
      else
        echo "⚠️ Kubernetes GPG key attempt $i failed, retrying..."
        sleep 5
        if [ $i -eq 3 ]; then
          echo "❌ Failed to add Kubernetes GPG key after 3 attempts"
          exit 1
        fi
      fi
    done
    
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
    
    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
    
    systemctl enable kubelet
    systemctl restart kubelet || echo "Kubelet will be started by kubeadm"
    
    # Verify installations
    docker --version || { echo "❌ Docker not working"; exit 1; }
    kubeadm version || { echo "❌ kubeadm not working"; exit 1; }
    kubectl version --client || { echo "❌ kubectl not working"; exit 1; }
    
    echo "✅ Common setup completed"
  SCRIPT

  # IMPROVED: Registry configuration with better networking support
  $configure_insecure_registry = <<-'SCRIPT'
    echo "=== Configuring insecure registry ==="
    
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "insecure-registries": ["192.168.56.10:5000"],
  "registry-mirrors": []
}
EOF
    
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    sed -i 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.9"|' /etc/containerd/config.toml
    
    # IMPROVED: More robust containerd registry config
    cat >> /etc/containerd/config.toml << 'EOF'

[plugins."io.containerd.grpc.v1.cri".registry]
  config_path = ""

[plugins."io.containerd.grpc.v1.cri".registry.mirrors]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.56.10:5000"]
    endpoint = ["http://192.168.56.10:5000"]

[plugins."io.containerd.grpc.v1.cri".registry.configs]
  [plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.56.10:5000".tls]
    insecure_skip_verify = true
  [plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.56.10:5000".auth]
    username = ""
    password = ""
EOF
    
    systemctl daemon-reload
    systemctl restart docker
    systemctl restart containerd
    systemctl restart kubelet || echo "Kubelet will restart automatically"
    
    sleep 10
    echo "✅ Insecure registry configured"
  SCRIPT

  # Docker registry setup (keeping your existing setup)
  $setup_registry = <<-'SCRIPT'
    echo "=== Setting up Docker Registry ==="
    
    mkdir -p /opt/registry
    
    docker pull registry:2 || {
      echo "⚠️ Failed to pull registry image, retrying..."
      sleep 10
      docker pull registry:2
    }
    
    docker stop local-registry 2>/dev/null || true
    docker rm local-registry 2>/dev/null || true
    
    docker run -d \
      -p 5000:5000 \
      --restart=always \
      --name local-registry \
      -v /opt/registry:/var/lib/registry \
      registry:2
    
    sleep 10
    
    if curl -s http://localhost:5000/v2/ >/dev/null; then
      echo "✅ Docker registry is running"
    else
      echo "⚠️ Registry test failed, but continuing..."
    fi
    
    echo "✅ Registry setup completed"
  SCRIPT

  # Master node with improved configuration
  config.vm.define "master" do |master|
    master.vm.hostname = "master"
    master.vm.network "private_network", ip: MASTER_IP
    
    master.vm.provider "virtualbox" do |vb|
      vb.memory = 4096  # Keep existing memory
      vb.cpus = 2
      vb.name = "k8s-master"
      vb.gui = true
    end
    
    master.vm.provision "shell", inline: $fix_dns
    master.vm.provision "shell", inline: $optimize_network
    master.vm.provision "shell", inline: $common_setup
    master.vm.provision "shell", inline: $configure_insecure_registry
    master.vm.provision "shell", inline: $setup_registry
    
    master.vm.provision "shell", inline: <<-SCRIPT
      set -e
      echo "=== Configuring Master Node ==="
      
      systemctl is-active docker || { echo "Docker not running"; exit 1; }
      systemctl is-active containerd || { echo "Containerd not running"; exit 1; }
      
      echo "KUBELET_EXTRA_ARGS=--node-ip=#{MASTER_IP}" > /etc/default/kubelet
      systemctl daemon-reload
      
      echo "=== Pre-pulling Kubernetes images ==="
      kubeadm config images pull
      
      echo "=== Initializing Kubernetes Cluster ==="
      # IMPROVED: Better kubeadm init with specific interface
      if ! kubeadm init \
        --apiserver-advertise-address=#{MASTER_IP} \
        --pod-network-cidr=#{POD_NETWORK_CIDR} \
        --ignore-preflight-errors=NumCPU \
        --control-plane-endpoint=#{MASTER_IP} \
        --v=5; then
        echo "❌ kubeadm init failed!"
        journalctl -u kubelet --no-pager -n 20
        exit 1
      fi
      
      echo "✅ Cluster initialized successfully"
      
      if [ ! -f /etc/kubernetes/admin.conf ]; then
        echo "❌ admin.conf not found!"
        exit 1
      fi
      
      mkdir -p /home/vagrant/.kube
      cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
      chown vagrant:vagrant /home/vagrant/.kube/config
      
      mkdir -p /root/.kube
      cp /etc/kubernetes/admin.conf /root/.kube/config
      
      export KUBECONFIG=/etc/kubernetes/admin.conf
      
      echo "Waiting for API server..."
      for i in {1..60}; do
        if kubectl get nodes &>/dev/null; then
          echo "✅ API server is responsive"
          break
        else
          echo "⏳ Waiting for API server... ($i/60)"
          sleep 5
        fi
        if [ $i -eq 60 ]; then
          echo "❌ API server failed to become responsive"
          exit 1
        fi
      done
      
      # IMPROVED: Use Calico instead of Flannel for better networking
      echo "=== Installing Calico network plugin ==="
      kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
      
      # Configure Calico for our pod CIDR
      cat > /tmp/custom-resources.yaml << 'EOF'
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF
      
      kubectl create -f /tmp/custom-resources.yaml
      
      echo "=== Waiting for cluster to be ready ==="
      kubectl wait --for=condition=Ready nodes --all --timeout=600s || {
        echo "❌ Nodes not ready within 10 minutes"
        kubectl get pods --all-namespaces
        kubectl get nodes -o wide
        exit 1
      }
      
      kubeadm token create --print-join-command > /vagrant/join-command.sh
      chmod +x /vagrant/join-command.sh
      
      kubectl taint nodes master node-role.kubernetes.io/control-plane:NoSchedule- || true
      
      # Test registry functionality
      echo "=== Testing registry functionality ==="
      if docker pull hello-world >/dev/null 2>&1; then
        docker tag hello-world 192.168.56.10:5000/hello-world:test
        if docker push 192.168.56.10:5000/hello-world:test >/dev/null 2>&1; then
          echo "✅ Registry push/pull test passed"
          docker rmi 192.168.56.10:5000/hello-world:test >/dev/null 2>&1 || true
        else
          echo "⚠️ Registry push test failed"
        fi
      else
        echo "⚠️ Could not test registry"
      fi
      
      echo "✅ Master node ready!"
      kubectl get nodes -o wide
    SCRIPT
  end
  
  # IMPROVED: Worker nodes with more resources
  ["worker1", "worker2"].each_with_index do |name, index|
    ip = index == 0 ? WORKER1_IP : WORKER2_IP
    
    config.vm.define name do |worker|
      worker.vm.hostname = name
      worker.vm.network "private_network", ip: ip
      
      worker.vm.provider "virtualbox" do |vb|
        vb.memory = 3072  # INCREASED from 2048 to 3072
        vb.cpus = 2
        vb.name = "k8s-#{name}"
        vb.gui = true
      end
      
      worker.vm.provision "shell", inline: $fix_dns
      worker.vm.provision "shell", inline: $optimize_network
      worker.vm.provision "shell", inline: $common_setup
      worker.vm.provision "shell", inline: $configure_insecure_registry
      
      worker.vm.provision "shell", inline: <<-SCRIPT
        echo "=== Configuring Worker Node: #{name} ==="
        
        echo "KUBELET_EXTRA_ARGS=--node-ip=#{ip}" > /etc/default/kubelet
        systemctl daemon-reload
        systemctl restart kubelet
        
        echo "=== Waiting for join command ==="
        while [ ! -f /vagrant/join-command.sh ]; do
          echo "Waiting for join command..."
          sleep 10
        done
        
        echo "=== Joining cluster ==="
        bash /vagrant/join-command.sh
        
        echo "✅ Worker node #{name} ready!"
      SCRIPT
    end
  end
  
  # ENHANCED: Cluster management information
  config.trigger.after :up do |trigger|
    trigger.name = "Cluster Information"
    trigger.ruby do |env, machine|
      if machine.name.to_s == "master"
        puts "\n🎉 Kubernetes cluster is ready!"
        puts "🌐 Network plugin: Calico (more stable than Flannel)"
        puts "🐳 Docker registry: 192.168.56.10:5000"
        puts "💾 Increased worker memory: 3GB each"
        puts "🔧 Enhanced networking optimizations applied"
        puts "\n📝 To access the cluster:"
        puts "   vagrant ssh master"
        puts "   kubectl get nodes"
        puts "\n📊 To view cluster status:"
        puts "   kubectl get pods --all-namespaces"
        puts "\n📦 Registry usage:"
        puts "   docker tag <image> 192.168.56.10:5000/<image>"
        puts "   docker push 192.168.56.10:5000/<image>"
        puts "\n🚀 Deploy your app:"
        puts "   kubectl apply -f your-deployments.yaml"
      end
    end
  end
end



# # -*- mode: ruby -*-
# # vi: set ft=ruby :

# # Configuration
# MASTER_IP = "192.168.56.10"
# WORKER1_IP = "192.168.56.11"
# WORKER2_IP = "192.168.56.12"
# POD_NETWORK_CIDR = "10.244.0.0/16"
# BOX_IMAGE = "ubuntu/focal64"
# K8S_VERSION = "1.28"

# Vagrant.configure("2") do |config|
#   config.vm.box = BOX_IMAGE
#   config.vm.box_check_update = false
  
#   # Global VM settings
#   config.vm.provider "virtualbox" do |vb|
#     vb.linked_clone = true
#     vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
#     vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
#     vb.customize ["modifyvm", :id, "--ioapic", "on"]
#   end

#   # Simple DNS fix script
#   $fix_dns = <<-'SCRIPT'
#     echo "=== Configuring DNS ==="
    
#     # Stop systemd-resolved if running
#     systemctl stop systemd-resolved 2>/dev/null || true
#     systemctl disable systemd-resolved 2>/dev/null || true
    
#     # Backup and replace resolv.conf
#     cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
    
#     # Create new resolv.conf
#     cat > /etc/resolv.conf << 'EOF'
# nameserver 8.8.8.8
# nameserver 8.8.4.4
# nameserver 1.1.1.1
# options timeout:2 attempts:3
# EOF
    
#     # Test DNS
#     echo "Testing DNS resolution..."
#     if ping -c 1 -W 3 google.com >/dev/null 2>&1; then
#       echo "✅ DNS working"
#     else
#       echo "⚠️ DNS test failed but continuing..."
#     fi
#   SCRIPT

#   # Common setup for all nodes
#   $common_setup = <<-'SCRIPT'
#     export DEBIAN_FRONTEND=noninteractive
    
#     echo "=== System Setup ==="
    
#     # Update system with better error handling
#     echo "=== Updating package lists ==="
#     apt-get update
    
#     echo "=== Upgrading system packages (non-critical) ==="
#     # Don't fail the entire script if upgrade has issues
#     apt-get upgrade -y || echo "⚠️ Some packages failed to upgrade, continuing..."
    
#     # Install essential packages
#     echo "=== Installing essential packages ==="
#     apt-get install -y \
#       apt-transport-https \
#       ca-certificates \
#       curl \
#       gpg \
#       software-properties-common \
#       wget \
#       vim \
#       htop || {
#       echo "❌ Failed to install essential packages"
#       exit 1
#     }
    
#     # From this point on, exit on any error for critical components
#     set -e
    
#     # Disable swap
#     echo "=== Disabling swap ==="
#     swapoff -a
#     sed -i '/swap/d' /etc/fstab
    
#     # Load kernel modules
#     cat > /etc/modules-load.d/k8s.conf << 'EOF'
# overlay
# br_netfilter
# EOF
    
#     modprobe overlay
#     modprobe br_netfilter
    
#     # Configure sysctl
#     cat > /etc/sysctl.d/99-kubernetes.conf << 'EOF'
# net.bridge.bridge-nf-call-iptables = 1
# net.bridge.bridge-nf-call-ip6tables = 1
# net.ipv4.ip_forward = 1
# EOF
    
#     sysctl --system
    
#     # Install Docker
#     echo "=== Installing Docker ==="
    
#     # Create keyrings directory
#     mkdir -p /etc/apt/keyrings
    
#     # Clean up any potential package issues
#     apt-get autoremove -y || true
#     apt-get autoclean || true
    
#     # Add Docker GPG key with retries
#     for i in {1..3}; do
#       if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
#         chmod a+r /etc/apt/keyrings/docker.gpg
#         echo "✅ Docker GPG key added successfully"
#         break
#       else
#         echo "⚠️ Docker GPG key attempt $i failed, retrying..."
#         sleep 5
#         if [ $i -eq 3 ]; then
#           echo "❌ Failed to add Docker GPG key after 3 attempts"
#           exit 1
#         fi
#       fi
#     done
    
#     # Add Docker repository
#     echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    
#     # Install Docker
#     apt-get update
#     apt-get install -y docker-ce docker-ce-cli containerd.io
    
#     echo "✅ Docker packages installed"
    
#     # Configure containerd
#     mkdir -p /etc/containerd
#     containerd config default > /etc/containerd/config.toml
    
#     # Enable systemd cgroup driver
#     sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
#     # Set the correct pause image
#     sed -i 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.9"|' /etc/containerd/config.toml
    
#     # Configure Docker
#     mkdir -p /etc/docker
#     cat > /etc/docker/daemon.json << 'EOF'
# {
#   "exec-opts": ["native.cgroupdriver=systemd"],
#   "log-driver": "json-file",
#   "log-opts": {
#     "max-size": "100m"
#   },
#   "storage-driver": "overlay2"
# }
# EOF
    
#     # Start services
#     systemctl daemon-reload
#     systemctl enable containerd docker
#     systemctl restart containerd
#     systemctl restart docker
    
#     # Wait for services to be ready
#     echo "Waiting for Docker and containerd..."
#     sleep 10
    
#     # Verify services are running
#     if ! systemctl is-active --quiet docker; then
#       echo "❌ Docker failed to start"
#       systemctl status docker --no-pager
#       exit 1
#     fi
    
#     if ! systemctl is-active --quiet containerd; then
#       echo "❌ Containerd failed to start"
#       systemctl status containerd --no-pager
#       exit 1
#     fi
    
#     echo "✅ Docker and containerd are running"
    
#     # Test Docker functionality
#     echo "=== Testing Docker ==="
#     if timeout 30 docker run --rm hello-world >/dev/null 2>&1; then
#       echo "✅ Docker test passed"
#     else
#       echo "⚠️ Docker test failed, but continuing..."
#     fi
    
#     # Add vagrant user to docker group
#     usermod -aG docker vagrant
    
#     # Install Kubernetes
#     echo "=== Installing Kubernetes ==="
    
#     # Ensure keyrings directory exists
#     mkdir -p /etc/apt/keyrings
    
#     # Add Kubernetes GPG key and repository with retries
#     for i in {1..3}; do
#       if curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg; then
#         echo "✅ Kubernetes GPG key added successfully"
#         break
#       else
#         echo "⚠️ Kubernetes GPG key attempt $i failed, retrying..."
#         sleep 5
#         if [ $i -eq 3 ]; then
#           echo "❌ Failed to add Kubernetes GPG key after 3 attempts"
#           exit 1
#         fi
#       fi
#     done
    
#     echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
    
#     # Install Kubernetes components
#     apt-get update
#     apt-get install -y kubelet kubeadm kubectl
#     apt-mark hold kubelet kubeadm kubectl
    
#     systemctl enable kubelet
    
#     # Restart kubelet to pick up new configuration
#     systemctl restart kubelet || echo "Kubelet will be started by kubeadm"
    
#     # Verify installations
#     echo "=== Verifying installations ==="
#     docker --version || { echo "❌ Docker not working"; exit 1; }
#     kubeadm version || { echo "❌ kubeadm not working"; exit 1; }
#     kubectl version --client || { echo "❌ kubectl not working"; exit 1; }
    
#     echo "✅ Common setup completed"
#   SCRIPT

#   # Master node
#   config.vm.define "master" do |master|
#     master.vm.hostname = "master"
#     master.vm.network "private_network", ip: MASTER_IP
    
#     master.vm.provider "virtualbox" do |vb|
#       vb.memory = 4096
#       vb.cpus = 2
#       vb.name = "k8s-master"
#       vb.gui = true
#     end
    
#     master.vm.provision "shell", inline: $fix_dns
#     master.vm.provision "shell", inline: $common_setup
    
#     master.vm.provision "shell", inline: <<-SCRIPT
#       set -e  # Exit on any error
#       echo "=== Configuring Master Node ==="
      
#       # Ensure all services are running
#       echo "=== Checking services ==="
#       systemctl is-active docker || { echo "Docker not running"; exit 1; }
#       systemctl is-active containerd || { echo "Containerd not running"; exit 1; }
#       systemctl is-active kubelet || echo "Kubelet will start with kubeadm"
      
#       # Configure kubelet
#       echo "KUBELET_EXTRA_ARGS=--node-ip=#{MASTER_IP}" > /etc/default/kubelet
#       systemctl daemon-reload
      
#       # Pull required images first
#       echo "=== Pre-pulling Kubernetes images ==="
#       kubeadm config images pull
      
#       # Initialize cluster with verbose output
#       echo "=== Initializing Kubernetes Cluster ==="
#       if ! kubeadm init \
#         --apiserver-advertise-address=#{MASTER_IP} \
#         --pod-network-cidr=#{POD_NETWORK_CIDR} \
#         --ignore-preflight-errors=NumCPU \
#         --v=5; then
#         echo "❌ kubeadm init failed!"
#         echo "Checking kubelet logs:"
#         journalctl -u kubelet --no-pager -n 20
#         exit 1
#       fi
      
#       echo "✅ Cluster initialized successfully"
      
#       # Verify admin.conf exists
#       if [ ! -f /etc/kubernetes/admin.conf ]; then
#         echo "❌ admin.conf not found!"
#         exit 1
#       fi
      
#       # Setup kubectl for vagrant user
#       mkdir -p /home/vagrant/.kube
#       cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
#       chown vagrant:vagrant /home/vagrant/.kube/config
      
#       # Setup kubectl for root
#       mkdir -p /root/.kube
#       cp /etc/kubernetes/admin.conf /root/.kube/config
      
#       # Test cluster connectivity
#       echo "=== Testing cluster connectivity ==="
#       export KUBECONFIG=/etc/kubernetes/admin.conf
      
#       # Wait for API server to be responsive
#       echo "Waiting for API server..."
#       for i in {1..60}; do
#         if kubectl get nodes &>/dev/null; then
#           echo "✅ API server is responsive"
#           break
#         else
#           echo "⏳ Waiting for API server... ($i/60)"
#           sleep 5
#         fi
#         if [ $i -eq 60 ]; then
#           echo "❌ API server failed to become responsive"
#           kubectl cluster-info dump || true
#           exit 1
#         fi
#       done
      
#       # Install network plugin (using Flannel for better compatibility)
#       echo "=== Installing Flannel network plugin ==="
#       kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
      
#       # Wait for nodes to be ready
#       echo "=== Waiting for cluster to be ready ==="
#       kubectl wait --for=condition=Ready nodes --all --timeout=300s || {
#         echo "❌ Nodes not ready within 5 minutes"
#         echo "Checking pod status:"
#         kubectl get pods --all-namespaces
#         echo "Checking node status:"
#         kubectl get nodes -o wide
#         echo "Checking flannel pods:"
#         kubectl get pods -n kube-flannel || true
#         exit 1
#       }
      
#       # Generate join command
#       kubeadm token create --print-join-command > /vagrant/join-command.sh
#       chmod +x /vagrant/join-command.sh
      
#       # Remove master taint (optional - allows scheduling on master)
#       kubectl taint nodes master node-role.kubernetes.io/control-plane:NoSchedule- || true
      
#       echo "✅ Master node ready!"
#       echo "📊 Cluster status:"
#       kubectl get nodes -o wide
#     SCRIPT
#   end
  
#   # Worker nodes
#   ["worker1", "worker2"].each_with_index do |name, index|
#     ip = index == 0 ? WORKER1_IP : WORKER2_IP
    
#     config.vm.define name do |worker|
#       worker.vm.hostname = name
#       worker.vm.network "private_network", ip: ip
      
#       worker.vm.provider "virtualbox" do |vb|
#         vb.memory = 2048
#         vb.cpus = 2
#         vb.name = "k8s-#{name}"
#         vb.gui = true
#       end
      
#       worker.vm.provision "shell", inline: $fix_dns
#       worker.vm.provision "shell", inline: $common_setup
      
#       worker.vm.provision "shell", inline: <<-SCRIPT
#         echo "=== Configuring Worker Node: #{name} ==="
        
#         # Configure kubelet
#         echo "KUBELET_EXTRA_ARGS=--node-ip=#{ip}" > /etc/default/kubelet
#         systemctl daemon-reload
#         systemctl restart kubelet
        
#         # Wait for join command
#         echo "=== Waiting for join command ==="
#         while [ ! -f /vagrant/join-command.sh ]; do
#           echo "Waiting for join command..."
#           sleep 10
#         done
        
#         # Join the cluster
#         echo "=== Joining cluster ==="
#         bash /vagrant/join-command.sh
        
#         echo "✅ Worker node #{name} ready!"
#       SCRIPT
#     end
#   end
  
#   # Convenience script for cluster management
#   config.trigger.after :up do |trigger|
#     trigger.name = "Cluster Information"
#     trigger.ruby do |env, machine|
#       if machine.name.to_s == "master"
#         puts "\n🎉 Kubernetes cluster is ready!"
#         puts "📝 To access the cluster:"
#         puts "   vagrant ssh master"
#         puts "   kubectl get nodes"
#         puts "\n📊 To view cluster status:"
#         puts "   kubectl get pods --all-namespaces"
#         puts "\n🔧 Join command saved in: ./join-command.sh"
#         puts "\n🌐 Network plugin: Flannel"
#         puts "📡 Pod CIDR: #{POD_NETWORK_CIDR}"
#         puts "🖥️  Master IP: #{MASTER_IP}"
#         puts "👷 Worker IPs: #{WORKER1_IP}, #{WORKER2_IP}"
#       end
#     end
#   end
# end