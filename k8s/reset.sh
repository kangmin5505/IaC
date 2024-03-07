#!/bin/bash

# author: kangmin
# email: km.kim2@okestro.com

# Reset kubenetest
sudo kubeadm reset

sudo rm -rf /etc/cni/net.d
sudo rm -rf ~/.kube
sudo rm -f ~/custom-resources-modified.yaml

sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X

# Re-enable AppArmor if it was previously disabled
sudo systemctl enable apparmor && sudo systemctl start apparmor

# Reload daemons and restart services to ensure they are in a clean state
sudo systemctl daemon-reload
sudo systemctl restart containerd
sudo systemctl restart kubelet

# Uninstall Docker and related packages
for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
    sudo apt-get purge -y $pkg
done
sudo apt-get autoremove -y

# Remove Docker apt repository and GPG key
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/keyrings/docker.asc

# Remove Kubernetes apt repository and GPG key
sudo rm -f /etc/apt/sources.list.d/kubernetes.list
sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Reset /etc/hosts to its original state
sudo mv /etc/hosts.bak /etc/hosts

# Restore original swap settings
sudo swapoff -a
sudo mv /etc/fstab.bak /etc/fstab
sudo swapon -a

# Remove Google DNS server from /etc/resolv.conf
sudo sed -i '/nameserver 8.8.8.8/d' /etc/resolv.conf

# Unload modules(overlay, br_netfilter)
sudo modprobe -r overlay
sudo modprobe -r br_netfilter
sudo rm -f /etc/modules-load.d/containerd.conf

# Remove sysctl settings for Kubernetes networking
sudo rm -f /etc/sysctl.d/kubernetes.conf
sudo sysctl --system &>/dev/null
