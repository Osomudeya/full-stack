# -*- mode: ruby -*-
# vi: set ft=ruby :

# Configure variables
MASTER_IP = "192.168.56.10"
WORKER1_IP = "192.168.56.11"
WORKER2_IP = "192.168.56.12"
POD_NETWORK_CIDR = "10.244.0.0/16"
BOX_IMAGE = "ubuntu/focal64"
KUBERNETES_VERSION = "1.28.0" # Without the -00 suffix

Vagrant.configure("2") do |config|
  config.vm.box = BOX_IMAGE
  config.vm.box_check_update = false

  # Fix DNS - separate standalone script
  $fix_dns = <<-SCRIPT
    echo "Setting up reliable DNS..."
    sudo systemctl disable systemd-resolved || true
    sudo systemctl stop systemd-resolved || true
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
    echo "options timeout:2 attempts:5" >> /etc/resolv.conf
    
    # Create service to preserve DNS across reboots
    cat > /etc/systemd/system/fix-dns.service << EOF
[Unit]
Description=Fix DNS Resolution
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo nameserver 8.8.8.8 > /etc/resolv.conf && echo nameserver 8.8.4.4 >> /etc/resolv.conf'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable fix-dns.service
    systemctl start fix-dns.service
    
    # Test DNS
    echo "Testing DNS..."
    ping -c 2 google.com || (echo "Google DNS not working, trying CloudFlare DNS..." && echo "nameserver 1.1.1.1" > /etc/resolv.conf && ping -c 2 google.com)
  SCRIPT

  # Main installation script
  $common_setup = <<-SCRIPT
    # Update system
    apt-get update
    
    # Install prerequisites
    apt-get install -y apt-transport-https ca-certificates curl gpg

    # Disable swap
    swapoff -a
    sed -i '/swap/d' /etc/fstab
    
    # Set up required kernel modules
    cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    
    modprobe overlay
    modprobe br_netfilter
    
    # Set up required sysctl params
    cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    sysctl --system
    
    # Install containerd
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y containerd.io
    
    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml > /dev/null
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    systemctl restart containerd
    systemctl enable containerd
    
    # Install Kubernetes packages
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
    apt-get update
    
    # Explicitly install without version to get the latest from the repo
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
    
    # Install other useful tools
    apt-get install -y jq vim git htop
  SCRIPT

  # Master node
  config.vm.define "master" do |master|
    master.vm.hostname = "master"
    master.vm.network "private_network", ip: MASTER_IP
    
    master.vm.provider "virtualbox" do |vb|
      vb.memory = 2048
      vb.cpus = 2
      vb.name = "k8s-master"
      vb.gui = true  # For debugging
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    end
    
    master.vm.provision "shell", inline: $fix_dns
    master.vm.provision "shell", inline: $common_setup
    
    master.vm.provision "shell", inline: <<-SCRIPT
      # Configure kubelet
      echo "KUBELET_EXTRA_ARGS=--node-ip=#{MASTER_IP}" > /etc/default/kubelet
      systemctl daemon-reload
      systemctl restart kubelet
      systemctl enable kubelet
      
      # Initialize the control-plane
      kubeadm init --apiserver-advertise-address=#{MASTER_IP} --pod-network-cidr=#{POD_NETWORK_CIDR} --apiserver-cert-extra-sans=#{MASTER_IP} --ignore-preflight-errors=NumCPU
      
      # Set up kubectl for vagrant user
      mkdir -p /home/vagrant/.kube
      cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
      chown -R vagrant:vagrant /home/vagrant/.kube
      
      # Apply Calico network
      su - vagrant -c "kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml"
      
      # Generate join command
      kubeadm token create --print-join-command > /vagrant/join-command.sh
      chmod +x /vagrant/join-command.sh
      
      # Set up kubectl completion
      echo 'source <(kubectl completion bash)' >> /home/vagrant/.bashrc
      echo 'alias k=kubectl' >> /home/vagrant/.bashrc
    SCRIPT
  end

  # Worker Node 1
  config.vm.define "worker1" do |worker|
    worker.vm.hostname = "worker1"
    worker.vm.network "private_network", ip: WORKER1_IP
    
    worker.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
      vb.name = "k8s-worker1"
      vb.gui = true  # For debugging
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    end
    
    worker.vm.provision "shell", inline: $fix_dns
    worker.vm.provision "shell", inline: $common_setup
    
    worker.vm.provision "shell", inline: <<-SCRIPT
      # Configure kubelet
      echo "KUBELET_EXTRA_ARGS=--node-ip=#{WORKER1_IP}" > /etc/default/kubelet
      systemctl daemon-reload
      systemctl restart kubelet
      systemctl enable kubelet
      
      # Join the cluster
      if [ -f /vagrant/join-command.sh ]; then
        bash /vagrant/join-command.sh --ignore-preflight-errors=all
      else
        echo "Join command not found. Please check if master node is configured properly."
        exit 1
      fi
    SCRIPT
  end

  # Worker Node 2
  config.vm.define "worker2" do |worker|
    worker.vm.hostname = "worker2"
    worker.vm.network "private_network", ip: WORKER2_IP
    
    worker.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
      vb.name = "k8s-worker2" 
      vb.gui = true  # For debugging
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    end
    
    worker.vm.provision "shell", inline: $fix_dns
    worker.vm.provision "shell", inline: $common_setup
    
    worker.vm.provision "shell", inline: <<-SCRIPT
      # Configure kubelet
      echo "KUBELET_EXTRA_ARGS=--node-ip=#{WORKER2_IP}" > /etc/default/kubelet
      systemctl daemon-reload
      systemctl restart kubelet
      systemctl enable kubelet
      
      # Join the cluster
      if [ -f /vagrant/join-command.sh ]; then
        bash /vagrant/join-command.sh --ignore-preflight-errors=all
      else
        echo "Join command not found. Please check if master node is configured properly."
        exit 1
      fi
    SCRIPT
  end
end
