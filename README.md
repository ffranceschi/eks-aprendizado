# EKS Aprendizado

Projeto pessoal de estudo prático do Amazon EKS: criar e administrar clusters
Kubernetes gerenciados na AWS.

## Pré-requisitos

- Conta AWS com permissões para criar clusters EKS, VPCs, EC2 e roles IAM
  (para aprendizado, `AdministratorAccess` simplifica; em produção use um
  papel com escopo restrito).
- `aws-cli` v2 autenticado (`aws sts get-caller-identity` deve funcionar).
- `eksctl` (>= 0.227.0)
- `kubectl` (>= 1.28)
- `helm` (>= 3.12)

O módulo [`00-preparacao`](00-preparacao/) tem um script que verifica tudo isso.

## Conta e profile AWS

Este projeto usa a conta AWS `165690630776` através do profile
`ffranceschi-bedrock` (já configurado via SSO em `~/.aws/config`). Antes de
rodar qualquer script deste repositório, exporte o profile na sessão do
terminal:

```bash
export AWS_PROFILE=ffranceschi-bedrock
```

Se a sessão SSO tiver expirado, renove com:

```bash
aws sso login --profile ffranceschi-bedrock
```

## Aviso de custo

Um cluster EKS cobra ~US$0,10/hora só pelo control plane, mais o custo dos
nodes EC2. Por isso, cada módulo deste projeto usa um cluster **efêmero**:
você cria no início do estudo e destrói (`scripts/destroy.sh`) ao terminar.
Nunca deixe um cluster rodando sem necessidade.

## Módulos

| Módulo | Tema |
|---|---|
| [00-preparacao](00-preparacao/) | Ferramentas e credenciais |
| [01-primeiro-cluster](01-primeiro-cluster/) | Primeiro cluster EKS via eksctl |
| [02-workloads-networking](02-workloads-networking/) | Deployments, Services, Ingress, ALB Controller |
| 03-iam-seguranca | IRSA, RBAC, Pod Security *(em breve)* |
| 04-observabilidade | CloudWatch Container Insights, Prometheus/Grafana *(em breve)* |
| 05-scaling-custos | HPA, Cluster Autoscaler/Karpenter, Spot, Fargate *(em breve)* |

Siga os módulos em ordem. Cada um assume um cluster novo, não o de um módulo
anterior.

Design completo em
[`docs/superpowers/specs/2026-07-12-eks-aprendizado-design.md`](docs/superpowers/specs/2026-07-12-eks-aprendizado-design.md).
