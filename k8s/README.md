# Kubernetes Cluster All-In-One
## 구성 환경
- OS: Ubuntu 22.04
- Kernel Version: 5.15.0-97-generic
- CPU Architecture: x86_64

## 설치 목록
- Docker(v1.29)
- kubelet(latest), kubectl(latest), kubeadm(latest)
- tigera-operator(v3.27.2), calico(v3.27.2)

## 설치
1. vim install_k8s.sh
2. sudo chmod +755 install_k8s.sh
3. ./install_k8s.sh [control|worker] NETWORK_CIDR(if control)
