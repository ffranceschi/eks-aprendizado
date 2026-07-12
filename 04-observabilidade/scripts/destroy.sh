#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$DIR/cluster.yaml"

echo "Isso vai destruir o cluster eks-aprendizado-04 e todos os recursos associados (VPC, node group, etc.)."
read -r -p "Digite 'destruir' para confirmar: " CONFIRM

if [ "$CONFIRM" != "destruir" ]; then
  echo "Cancelado."
  exit 1
fi

eksctl delete cluster -f "$CONFIG"
