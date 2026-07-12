#!/usr/bin/env bash
set -euo pipefail

MISSING=0

check_tool() {
  local name="$1"
  shift
  if command -v "$name" >/dev/null 2>&1; then
    echo "OK   $name -> $("$@" 2>&1 | head -1)"
  else
    echo "FAIL $name não encontrado no PATH"
    MISSING=1
  fi
}

check_tool aws aws --version
check_tool eksctl eksctl version
check_tool kubectl kubectl version --client
check_tool helm helm version --short

echo

if aws sts get-caller-identity >/dev/null 2>&1; then
  IDENTITY="$(aws sts get-caller-identity --query Arn --output text)"
  echo "OK   aws sts get-caller-identity -> $IDENTITY"
else
  echo "FAIL aws sts get-caller-identity -> sem credenciais válidas (configure com 'aws configure' ou 'aws login')"
  MISSING=1
fi

echo

if [ "$MISSING" -eq 1 ]; then
  echo "Alguma verificação falhou. Resolva os itens acima antes de seguir para 01-primeiro-cluster."
  exit 1
fi

echo "Tudo pronto para começar."
