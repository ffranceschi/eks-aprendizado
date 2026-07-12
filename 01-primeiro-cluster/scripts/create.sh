#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$DIR/cluster.yaml"

echo "Isso vai criar um cluster EKS real na sua conta AWS."
echo "Custo aproximado: ~US\$0,10/h de control plane + custo dos nodes EC2 (2x t3.medium)."
read -r -p "Digite 'criar' para confirmar: " CONFIRM

if [ "$CONFIRM" != "criar" ]; then
  echo "Cancelado."
  exit 1
fi

eksctl create cluster -f "$CONFIG"

echo
echo "Cluster criado. Nodes:"
kubectl get nodes
