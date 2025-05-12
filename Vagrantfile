# -*- mode: ruby -*-
# vi: set ft=ruby :

MASTER_IP = "192.168.56.10"
BOX_IMAGE = "ubuntu/focal64"
MASTER_MEMORY = 4096
MASTER_CPU = 2
WORKER_MEMORY = 3072
WORKER_CPU = 2
WORKER_COUNT = 2

Vagrant.configure("2") do |config|
  config.vm.box = BOX_IMAGE
  config.vm.box_check_update = false

  # Master node
  config.vm.define "master" do |master|
    master.vm.hostname = "master"
    master.vm.network "private_network", ip: MASTER_IP
    
    master.vm.provider "virtualbox" do |vb|
      vb.memory = MASTER_MEMORY
      vb.cpus = MASTER_CPU
      vb.name = "memory-game-master"
      vb.gui = true  # Show the VM console for debugging
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
    end
    
    # Forward ports for development
    master.vm.network "forwarded_port", guest: 80, host: 80
    master.vm.network "forwarded_port", guest: 443, host: 443
    master.vm.network "forwarded_port", guest: 6443, host: 6443
  end

  # Worker nodes
  (1..WORKER_COUNT).each do |i|
    config.vm.define "worker#{i}" do |worker|
      worker_ip = "192.168.56.#{10 + i}"
      worker.vm.hostname = "worker#{i}"
      worker.vm.network "private_network", ip: worker_ip
      
      worker.vm.provider "virtualbox" do |vb|
        vb.memory = WORKER_MEMORY
        vb.cpus = WORKER_CPU
        vb.name = "memory-game-worker#{i}"
        vb.gui = true  # Show the VM console for debugging
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
        vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      end
    end
  end
end
