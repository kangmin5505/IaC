#!/bin/bash
# install_k8s.sh

# author: kangmin
# email: km.kim2@okestro.com

validate_cidr() {
	local cidr=$1
	if ! echo $cidr | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; then
		echo "Error: The NETWORK_CIDR argument is not in a valid CIDR format.(i.g., 192.168.0.0/16)"
		exit 1
	fi
}

validate_arguments() {
	if [ $# -lt 1 ]; then
		echo "Error: No arguments provided."
		echo "Usage: $0 [control|worker] [NETWORK_CIDR (if control)]"
		exit 1
	fi

	NODE=$1
	if [ "$NODE" != "control" ] && [ "$NODE" != "worker" ]; then
		echo "Error: First argument must be 'control' or 'worker'."
		exit 1
	fi

	# If the role is master, check for the second argument
	if [ "$NODE" = "control" ]; then
		if [ $# -lt 2 ]; then
			echo "Error: 'control' node requires a NETWORK_CIDR argument."
			exit 1
		fi
		NETWORK_CIDR=$2
		validate_cidr $NETWORK_CIDR
	fi

}

validate_arguments "$@"

# Append in and hostname into /etc/hosts
output=$(ip route show default | awk '{print $9}')" "$(hostname)
sudo cp /etc/hosts /etc/hosts.bak
sudo sh -c "echo '$output\n$(cat /etc/hosts)' > /etc/hosts"

# Off swap temporarily and permanently
sudo swapoff -a
sudo cp /etc/fstab /etc/fstab.bak
sudo sh -c "sed -i.bak -r 's/(.+swap.+)/#\1/' /etc/fstab"

# Add google DNS server to /etc/resolv.conf
sudo sh -c "echo 'nameserver 8.8.8.8' >> /etc/resolv.conf"

# Check required ports
if nc -zv 127.0.0.1 6443 &>/dev/null; then
	echo "[Fail - Port 6443 is open]"
	exit 0
fi

# Load modules(overlay, br_netfilter)
sudo sh -c "cat > /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF"
sudo modprobe overlay
sudo modprobe br_netfilter

sudo sh -c "cat > /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF"
sudo sysctl --system &>/dev/null

# Install Docker
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
	sudo apt-get remove $pkg >/dev/null 2>&1
done
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

sudo rm -f /etc/containerd/config.toml

# Initialize kubernetes on Control Node
sudo sh -c "cat > /etc/default/kubelet <<EOF
KUBELET_EXTRA_ARGS='--cgroup-driver=cgroupfs'
EOF"
sudo systemctl daemon-reload && sudo systemctl restart kubelet
sudo sh -c "cat > /etc/docker/daemon.json <<EOF
{
      "exec-opts": ["native.cgroupdriver=systemd"],
      "log-driver": "json-file",
      "log-opts": {
      "max-size": "100m"
   },
       "storage-driver": "overlay2"
}
EOF"
sudo systemctl daemon-reload && sudo systemctl restart containerd

# Install kubeadm, kubelet and kubectl
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Initialize kubeadm
if [ $NODE = "control" ]; then
	sudo kubeadm init --pod-network-cidr="$NETWORK_CIDR" --token-ttl 0

	mkdir -p $HOME/.kube
	sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
	sudo chown $(id -u):$(id -g) $HOME/.kube/config

	kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/tigera-operator.yaml

	curl https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/custom-resources.yaml | \
	sed "s|192.168.0.0/6|$NETWORK_CIDR|g" > custom-resources-modified.yaml

	kubectl apply -f custom-resources-modified.yaml
fi

sudo systemctl stop apparmor && sudo systemctl disable apparmor
sudo systemctl restart containerd
sudo systemctl restart kubelet
