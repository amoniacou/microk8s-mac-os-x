#!/bin/bash

echo "Checking..."
vms=$(multipass list 2>/dev/null | grep microk8s-vm | wc -l)

if [[ ${vms} > 0 ]]; then
    echo "microk8s already installed!!!"
    exit 1
fi

function kmerge() {
    KUBECONFIG=~/.kube/config:$1 kubectl config view --flatten > ~/.kube/mergedkub && mv ~/.kube/mergedkub ~/.kube/config
}

echo "Install requirements..."
brew install hyperkit dnsmasq kubernetes-cli
echo "Setup basic dnsmasq config..."
cat <<EOF > /usr/local/etc/dnsmasq.conf
listen-address=127.0.0.1,192.168.64.1
EOF
echo "Install multipass"
brew cask install multipass
echo "Init microk8s vm..."
multipass launch --name microk8s-vm --cpus 3 --mem 4G --disk 40G --cloud-init cloud-init.yaml
if [[ $? != 0 ]]; then
    echo "Unable to run VM"
    exit 1
fi
vms=$(multipass list | grep microk8s-vm | wc -l)

if [[ ${vms} == 0 ]]; then
    echo "No microk8s VM\!"
    exit 1
fi

if [[ `multipass exec microk8s-vm -- sudo microk8s.status | grep "microk8s is running" | wc -l` == 0 ]]; then
    echo "No microk8s is running\!"
    exit 1
fi

ip=$(multipass list | grep microk8s-vm | awk '{print $3}')
echo "IP of microk8s is ${ip}"
cat <<EOF >> /usr/local/etc/dnsmasq.conf
address=/test/${ip}
EOF
echo "Running dnsmasq"
sudo brew services start dnsmasq
echo "\n\n\n"
echo "========================================"
echo "Please add 127.0.0.1 to your DNS servers"
echo "========================================"
echo "\n\n\n"
echo "Merge kubectl configs"
multipass exec microk8s-vm -- sudo /snap/bin/microk8s.config > ~/.kube/micro.config
kmerge ~/.kube/micro.config
rm ~/.kube/micro.config
echo "Switch kubectl context to microk8s"
kubectl config use-context microk8s
echo "Install cert manager"
kubectl create namespace cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo add stable https://kubernetes-charts.storage.googleapis.com
helm repo update
helm install \
cert-manager jetstack/cert-manager \
--namespace cert-manager \
--version v0.13.0 --replace
echo "Install ingress-nginx"
helm install nginx-ingress stable/nginx-ingress -f ./ingress_values.yaml
