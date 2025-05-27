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
  
  # Global VM settings
  config.vm.provider "virtualbox" do |vb|
    vb.linked_clone = true
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
    vb.customize ["modifyvm", :id, "--ioapic", "on"]
  end

  # Simple DNS fix script
  $fix_dns = <<-'SCRIPT'
    echo "=== Configuring DNS ==="
    
    # Stop systemd-resolved if running
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true
    
    # Backup and replace resolv.conf
    cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
    
    # Create new resolv.conf
    cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
options timeout:2 attempts:3
EOF
    
    # Test DNS
    echo "Testing DNS resolution..."
    if ping -c 1 -W 3 google.com >/dev/null 2>&1; then
      echo "✅ DNS working"
    else
      echo "⚠️ DNS test failed but continuing..."
    fi
  SCRIPT

  # Common setup for all nodes
  $common_setup = <<-'SCRIPT'
    export DEBIAN_FRONTEND=noninteractive
    
    echo "=== System Setup ==="
    
    # Update system with better error handling
    echo "=== Updating package lists ==="
    apt-get update
    
    echo "=== Upgrading system packages (non-critical) ==="
    # Don't fail the entire script if upgrade has issues
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
      htop || {
      echo "❌ Failed to install essential packages"
      exit 1
    }
    
    # From this point on, exit on any error for critical components
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
    
    # Configure sysctl
    cat > /etc/sysctl.d/99-kubernetes.conf << 'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
    
    sysctl --system
    
    # Install Docker
    echo "=== Installing Docker ==="
    
    # Create keyrings directory
    mkdir -p /etc/apt/keyrings
    
    # Clean up any potential package issues
    apt-get autoremove -y || true
    apt-get autoclean || true
    
    # Add Docker GPG key with retries
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
    
    # Add Docker repository
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    
    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    
    echo "✅ Docker packages installed"
    
    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    
    # Enable systemd cgroup driver
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    # Set the correct pause image
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
    
    # Wait for services to be ready
    echo "Waiting for Docker and containerd..."
    sleep 10
    
    # Verify services are running
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
    echo "=== Testing Docker ==="
    if timeout 30 docker run --rm hello-world >/dev/null 2>&1; then
      echo "✅ Docker test passed"
    else
      echo "⚠️ Docker test failed, but continuing..."
    fi
    
    # Add vagrant user to docker group
    usermod -aG docker vagrant
    
    # Install Kubernetes
    echo "=== Installing Kubernetes ==="
    
    # Ensure keyrings directory exists
    mkdir -p /etc/apt/keyrings
    
    # Add Kubernetes GPG key and repository with retries
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
    
    # Install Kubernetes components
    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
    
    systemctl enable kubelet
    
    # Restart kubelet to pick up new configuration
    systemctl restart kubelet || echo "Kubelet will be started by kubeadm"
    
    # Verify installations
    echo "=== Verifying installations ==="
    docker --version || { echo "❌ Docker not working"; exit 1; }
    kubeadm version || { echo "❌ kubeadm not working"; exit 1; }
    kubectl version --client || { echo "❌ kubectl not working"; exit 1; }
    
    echo "✅ Common setup completed"
  SCRIPT

  # Master node
  config.vm.define "master" do |master|
    master.vm.hostname = "master"
    master.vm.network "private_network", ip: MASTER_IP
    
    master.vm.provider "virtualbox" do |vb|
      vb.memory = 4096
      vb.cpus = 2
      vb.name = "k8s-master"
      vb.gui = true
    end
    
    master.vm.provision "shell", inline: $fix_dns
    master.vm.provision "shell", inline: $common_setup
    
    master.vm.provision "shell", inline: <<-SCRIPT
      set -e  # Exit on any error
      echo "=== Configuring Master Node ==="
      
      # Ensure all services are running
      echo "=== Checking services ==="
      systemctl is-active docker || { echo "Docker not running"; exit 1; }
      systemctl is-active containerd || { echo "Containerd not running"; exit 1; }
      systemctl is-active kubelet || echo "Kubelet will start with kubeadm"
      
      # Configure kubelet
      echo "KUBELET_EXTRA_ARGS=--node-ip=#{MASTER_IP}" > /etc/default/kubelet
      systemctl daemon-reload
      
      # Pull required images first
      echo "=== Pre-pulling Kubernetes images ==="
      kubeadm config images pull
      
      # Initialize cluster with verbose output
      echo "=== Initializing Kubernetes Cluster ==="
      if ! kubeadm init \
        --apiserver-advertise-address=#{MASTER_IP} \
        --pod-network-cidr=#{POD_NETWORK_CIDR} \
        --ignore-preflight-errors=NumCPU \
        --v=5; then
        echo "❌ kubeadm init failed!"
        echo "Checking kubelet logs:"
        journalctl -u kubelet --no-pager -n 20
        exit 1
      fi
      
      echo "✅ Cluster initialized successfully"
      
      # Verify admin.conf exists
      if [ ! -f /etc/kubernetes/admin.conf ]; then
        echo "❌ admin.conf not found!"
        exit 1
      fi
      
      # Setup kubectl for vagrant user
      mkdir -p /home/vagrant/.kube
      cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
      chown vagrant:vagrant /home/vagrant/.kube/config
      
      # Setup kubectl for root
      mkdir -p /root/.kube
      cp /etc/kubernetes/admin.conf /root/.kube/config
      
      # Test cluster connectivity
      echo "=== Testing cluster connectivity ==="
      export KUBECONFIG=/etc/kubernetes/admin.conf
      
      # Wait for API server to be responsive
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
          kubectl cluster-info dump || true
          exit 1
        fi
      done
      
      # Install network plugin (using Flannel for better compatibility)
      echo "=== Installing Flannel network plugin ==="
      kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
      
      # Wait for nodes to be ready
      echo "=== Waiting for cluster to be ready ==="
      kubectl wait --for=condition=Ready nodes --all --timeout=300s || {
        echo "❌ Nodes not ready within 5 minutes"
        echo "Checking pod status:"
        kubectl get pods --all-namespaces
        echo "Checking node status:"
        kubectl get nodes -o wide
        echo "Checking flannel pods:"
        kubectl get pods -n kube-flannel || true
        exit 1
      }
      
      # Generate join command
      kubeadm token create --print-join-command > /vagrant/join-command.sh
      chmod +x /vagrant/join-command.sh
      
      # Remove master taint (optional - allows scheduling on master)
      kubectl taint nodes master node-role.kubernetes.io/control-plane:NoSchedule- || true
      
      echo "✅ Master node ready!"
      echo "📊 Cluster status:"
      kubectl get nodes -o wide
    SCRIPT
  end
  
  # Worker nodes
  ["worker1", "worker2"].each_with_index do |name, index|
    ip = index == 0 ? WORKER1_IP : WORKER2_IP
    
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
        echo "=== Configuring Worker Node: #{name} ==="
        
        # Configure kubelet
        echo "KUBELET_EXTRA_ARGS=--node-ip=#{ip}" > /etc/default/kubelet
        systemctl daemon-reload
        systemctl restart kubelet
        
        # Wait for join command
        echo "=== Waiting for join command ==="
        while [ ! -f /vagrant/join-command.sh ]; do
          echo "Waiting for join command..."
          sleep 10
        done
        
        # Join the cluster
        echo "=== Joining cluster ==="
        bash /vagrant/join-command.sh
        
        echo "✅ Worker node #{name} ready!"
      SCRIPT
    end
  end
  
  # Convenience script for cluster management
  config.trigger.after :up do |trigger|
    trigger.name = "Cluster Information"
    trigger.ruby do |env, machine|
      if machine.name.to_s == "master"
        puts "\n🎉 Kubernetes cluster is ready!"
        puts "📝 To access the cluster:"
        puts "   vagrant ssh master"
        puts "   kubectl get nodes"
        puts "\n📊 To view cluster status:"
        puts "   kubectl get pods --all-namespaces"
        puts "\n🔧 Join command saved in: ./join-command.sh"
        puts "\n🌐 Network plugin: Flannel"
        puts "📡 Pod CIDR: #{POD_NETWORK_CIDR}"
        puts "🖥️  Master IP: #{MASTER_IP}"
        puts "👷 Worker IPs: #{WORKER1_IP}, #{WORKER2_IP}"
      end
    end
  end
end