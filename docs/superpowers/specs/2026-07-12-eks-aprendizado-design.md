# Design: Projeto de aprendizado de EKS

Data: 2026-07-12

## Contexto

Projeto pessoal para aprender a fazer deploy e administrar um cluster Amazon EKS.
O repositório está vazio (apenas metadados do IDE). Perfil de partida: experiência
sólida em AWS, pouca experiência com Kubernetes.

## Objetivo

Construir, através de módulos práticos e independentes, o conhecimento necessário
para criar e administrar um cluster EKS, cobrindo:

1. Deploy de workloads e networking
2. IAM e segurança
3. Observabilidade
4. Scaling e custos

## Decisões

- **Provisionamento**: `eksctl` (ferramenta oficial da AWS para EKS), preferido
  por simplicidade em relação a Terraform/CDK para focar no aprendizado dos
  conceitos do EKS em si.
- **Ciclo de vida do cluster**: efêmero por módulo. Cada módulo cria seu próprio
  cluster no início e o destrói ao final da sessão de estudo, para minimizar
  custos (~$0,10/h de control plane + custo dos nodes). Módulos não reaproveitam
  o cluster de módulos anteriores.
- **Formato de conteúdo**: guia em Markdown (conceitos + passo a passo) mais
  código (config do eksctl, manifests Kubernetes, scripts).

## Estrutura de pastas

```
eks-aprendizado/
├── README.md
├── 00-preparacao/
│   └── README.md
├── 01-primeiro-cluster/
│   ├── README.md
│   ├── cluster.yaml
│   └── scripts/
│       ├── create.sh
│       └── destroy.sh
├── 02-workloads-networking/
│   ├── README.md
│   ├── cluster.yaml
│   ├── scripts/
│   └── manifests/
├── 03-iam-seguranca/
│   ├── README.md
│   ├── cluster.yaml
│   ├── scripts/
│   └── manifests/
├── 04-observabilidade/
│   ├── README.md
│   ├── cluster.yaml
│   ├── scripts/
│   └── manifests/
├── 05-scaling-custos/
│   ├── README.md
│   ├── cluster.yaml
│   ├── scripts/
│   └── manifests/
└── docs/superpowers/specs/
```

### Convenção por módulo

- `README.md`: conceitos explicados, passo a passo, o que observar/validar,
  e um comando de limpeza no final.
- `cluster.yaml`: config do `eksctl` para o cluster daquele módulo (quando
  aplicável).
- `scripts/create.sh` e `scripts/destroy.sh`: ciclo de vida efêmero do cluster.
- `manifests/`: YAMLs de Kubernetes (Deployments, Services, etc.) organizados
  por módulo.

## Conteúdo por módulo

### 00-preparacao
Sem cluster. Garante que as ferramentas necessárias estão instaladas e
configuradas: `aws-cli` (autenticado), `eksctl`, `kubectl`, `helm`. Checklist
de verificação (`aws sts get-caller-identity`, versões mínimas de cada CLI).

### 01-primeiro-cluster
Primeiro cluster EKS via `eksctl create cluster`. Anatomia de um cluster EKS
(control plane gerenciado pela AWS, node groups, VPC criada), `kubectl`
apontando para o cluster, exploração básica (`kubectl get nodes`,
`kubectl cluster-info`). Encerra com `eksctl delete cluster`.

### 02-workloads-networking
Deployments, Services (ClusterIP/NodePort/LoadBalancer), ConfigMaps/Secrets,
Ingress via AWS Load Balancer Controller (IRSA necessário para o controller),
noção de VPC CNI e IPs de pods dentro da VPC. Deploy de uma aplicação simples
exposta publicamente.

### 03-iam-seguranca
IRSA (IAM Roles for Service Accounts) em profundidade, RBAC do Kubernetes
(Roles/RoleBindings/ClusterRoles), Pod Security Standards, gestão de Secrets
(nativo + integração com AWS Secrets Manager/External Secrets se coerente).

### 04-observabilidade
CloudWatch Container Insights (agente/EKS add-on), métricas e logs de
cluster/pods. Introdução a Prometheus + Grafana no cluster (via Helm) como
alternativa/complemento open-source.

### 05-scaling-custos
Horizontal Pod Autoscaler (HPA), Cluster Autoscaler vs. Karpenter, node groups
gerenciados vs. self-managed, Fargate profiles, uso de Spot instances para
reduzir custo. Discussão de trade-offs de custo x resiliência.

## Fora de escopo (por ora)

- CI/CD e GitOps (ArgoCD/Flux) — não foi selecionado como prioridade.
- Terraform/CDK — descartado em favor de `eksctl` para este aprendizado.
- Multi-cluster, multi-região, DR.

## Critério de conclusão

Cada módulo é considerado "concluído" quando o guia foi seguido, o cluster foi
criado e destruído com sucesso, e os conceitos-chave do README foram
verificados na prática (ex: `kubectl` mostrando o recurso esperado, IRSA
funcionando, métricas aparecendo no CloudWatch/Grafana).
