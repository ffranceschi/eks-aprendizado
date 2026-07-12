#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$DIR/cluster.yaml"

echo "Isso vai destruir o cluster eks-aprendizado-05 e todos os recursos associados (VPC, node groups, etc.)."
echo "Se você instalou o Karpenter, delete o NodePool ANTES deste script"
echo "('kubectl delete -f manifests/karpenter-nodepool.yaml') para ele desprovisionar os nodes que criou — senão podem ficar instâncias EC2 órfãs fora do CloudFormation."
read -r -p "Digite 'destruir' para confirmar: " CONFIRM

if [ "$CONFIRM" != "destruir" ]; then
  echo "Cancelado."
  exit 1
fi

eksctl delete cluster -f "$CONFIG"
