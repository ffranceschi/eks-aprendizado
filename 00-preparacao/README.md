# 00 — Preparação

Antes de criar qualquer cluster, garanta que as ferramentas e credenciais
estão prontas. Este módulo não cria nenhum recurso na AWS.

## O que você precisa

- **aws-cli v2** autenticado em uma conta AWS onde você pode criar clusters
  EKS, VPCs, EC2 e roles IAM.
- **eksctl** — ferramenta oficial de linha de comando para EKS.
- **kubectl** — cliente Kubernetes.
- **helm** — gerenciador de pacotes Kubernetes (usado em módulos futuros).

## Verificação

Rode o script de verificação:

```bash
./verify.sh
```

Ele confere se cada ferramenta está instalada e se o `aws-cli` tem
credenciais válidas (via `aws sts get-caller-identity`). Se algo faltar, o
script termina com `FAIL` na linha correspondente e código de saída `1`.

Se `aws sts get-caller-identity` falhar, configure credenciais com
`aws configure` (access key/secret) ou `aws login` (SSO), dependendo de como
sua organização gerencia acesso.

## Próximo passo

Com tudo `OK`, siga para [`01-primeiro-cluster`](../01-primeiro-cluster/).
