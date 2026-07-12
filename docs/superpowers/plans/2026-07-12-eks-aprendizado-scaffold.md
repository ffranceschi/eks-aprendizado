# EKS Aprendizado — Scaffold + Módulos 00/01 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar a estrutura base do repositório de aprendizado de EKS e os dois primeiros módulos: `00-preparacao` (checklist de ferramentas) e `01-primeiro-cluster` (primeiro cluster EKS via `eksctl`, efêmero).

**Architecture:** Repositório de documentação + scripts, sem build/runtime próprio. Cada módulo é uma pasta autocontida com `README.md` (guia), e quando aplicável `cluster.yaml` (config do `eksctl`) e `scripts/create.sh` + `scripts/destroy.sh` (ciclo de vida efêmero do cluster). "Testes" aqui significam validação estática (sintaxe de shell, sintaxe/schema de YAML) — nunca a criação real de um cluster AWS, que é uma ação manual e cara feita pelo usuário quando ele decidir estudar aquele módulo.

**Tech Stack:** `eksctl` 0.227.0+, `kubectl` 1.28+, `helm` 3.12+ (ou compatível), `aws-cli` v2, Bash, YAML.

## Global Constraints

- Provisionamento exclusivamente via `eksctl` (config declarativa em `cluster.yaml`), não Terraform/CDK.
- Clusters são efêmeros por módulo: cada módulo cria e destrói seu próprio cluster; módulos não reaproveitam cluster de módulos anteriores.
- Todo módulo com cluster tem `README.md` + `cluster.yaml` + `scripts/create.sh` + `scripts/destroy.sh`.
- `create.sh` e `destroy.sh` SEMPRE pedem confirmação explícita digitada pelo usuário antes de agir, pois criam/destroem recursos AWS reais e cobrados.
- Nenhuma tarefa de implementação deste plano deve executar `eksctl create cluster` de fato (sem `--dry-run`) — isso é uma ação manual do usuário, fora do escopo de "implementar o plano".
- Formato de conteúdo: guia em Markdown + código, em português (idioma usado pelo usuário nesta conversa).

---

### Task 1: README raiz do projeto

**Files:**
- Create: `README.md`
- Create: `.gitignore`

**Interfaces:**
- Produces: ponto de entrada do repositório, referenciado pelos READMEs de cada módulo (link relativo `00-preparacao/`, `01-primeiro-cluster/`).

- [ ] **Step 1: Criar `.gitignore`**

```gitignore
# kubeconfig e credenciais locais que scripts possam gerar
kubeconfig*
*.kubeconfig
.envrc

# artefatos de SO/editor
.DS_Store
```

- [ ] **Step 2: Criar `README.md` na raiz**

```markdown
# EKS Aprendizado

Projeto pessoal de estudo prático do Amazon EKS: criar e administrar clusters
Kubernetes gerenciados na AWS.

## Pré-requisitos

- Conta AWS com permissões para criar clusters EKS, VPCs, EC2 e roles IAM
  (para aprendizado, `AdministratorAccess` simplifica; em produção use um
  papel com escopo restrito).
- `aws-cli` v2 autenticado (`aws sts get-caller-identity` deve funcionar).
- `eksctl` (>= 0.180.0)
- `kubectl` (>= 1.28)
- `helm` (>= 3.12)

O módulo [`00-preparacao`](00-preparacao/) tem um script que verifica tudo isso.

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
| 02-workloads-networking | Deployments, Services, Ingress, ALB Controller *(em breve)* |
| 03-iam-seguranca | IRSA, RBAC, Pod Security *(em breve)* |
| 04-observabilidade | CloudWatch Container Insights, Prometheus/Grafana *(em breve)* |
| 05-scaling-custos | HPA, Cluster Autoscaler/Karpenter, Spot, Fargate *(em breve)* |

Siga os módulos em ordem. Cada um assume um cluster novo, não o de um módulo
anterior.

Design completo em
[`docs/superpowers/specs/2026-07-12-eks-aprendizado-design.md`](docs/superpowers/specs/2026-07-12-eks-aprendizado-design.md).
```

- [ ] **Step 3: Commit**

```bash
git add README.md .gitignore
git commit -m "Add root README and gitignore for EKS learning project"
```

---

### Task 2: Módulo 00-preparacao

**Files:**
- Create: `00-preparacao/README.md`
- Create: `00-preparacao/verify.sh`

**Interfaces:**
- Consumes: nenhuma (primeiro módulo, sem dependências de código).
- Produces: `verify.sh` — script executável, sem argumentos, saída em stdout com linhas `OK`/`FAIL` por ferramenta, `exit 1` se algo falhar, `exit 0` se tudo OK. Módulos seguintes podem reusar o padrão de saída mas não o script em si.

- [ ] **Step 1: Criar `00-preparacao/verify.sh`**

```bash
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
```

- [ ] **Step 2: Tornar o script executável**

```bash
chmod +x 00-preparacao/verify.sh
```

- [ ] **Step 3: Checar sintaxe do script**

Run: `bash -n 00-preparacao/verify.sh`
Expected: nenhuma saída, exit code 0.

- [ ] **Step 4: Executar o script de verdade (é somente leitura, seguro)**

Run: `./00-preparacao/verify.sh; echo "exit code: $?"`
Expected: uma linha `OK`/`FAIL` por ferramenta (`aws`, `eksctl`, `kubectl`, `helm`), depois o resultado de `aws sts get-caller-identity`. Neste ambiente, como o `aws-cli` ainda não está autenticado, espera-se `FAIL` na linha de `aws sts get-caller-identity` e `exit code: 1` — isso confirma que o script detecta corretamente credenciais ausentes.

- [ ] **Step 5: Criar `00-preparacao/README.md`**

```markdown
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
```

- [ ] **Step 6: Commit**

```bash
git add 00-preparacao/
git commit -m "Add module 00-preparacao: tooling and credentials checklist"
```

---

### Task 3: Módulo 01-primeiro-cluster

**Files:**
- Create: `01-primeiro-cluster/README.md`
- Create: `01-primeiro-cluster/cluster.yaml`
- Create: `01-primeiro-cluster/scripts/create.sh`
- Create: `01-primeiro-cluster/scripts/destroy.sh`

**Interfaces:**
- Consumes: nenhuma diretamente, mas o README assume que `00-preparacao/verify.sh` já passou.
- Produces: `cluster.yaml` — nome do cluster `eks-aprendizado-01`, consumido por `scripts/create.sh` e `scripts/destroy.sh` via `eksctl ... -f cluster.yaml`. Módulos futuros (02+) terão seu próprio `cluster.yaml` com nome distinto — não reaproveitam este arquivo.

- [ ] **Step 1: Criar `01-primeiro-cluster/cluster.yaml`**

```yaml
# Config do eksctl para o primeiro cluster de estudo.
# Edite "region" abaixo se quiser usar outra região AWS.
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: eks-aprendizado-01
  region: us-east-1
  version: "1.31"

managedNodeGroups:
  - name: ng-estudo
    instanceType: t3.medium
    desiredCapacity: 2
    minSize: 2
    maxSize: 2
    volumeSize: 20
    labels:
      modulo: 01-primeiro-cluster
```

- [ ] **Step 2: Checar sintaxe YAML pura**

Run: `python3 -c "import yaml; yaml.safe_load(open('01-primeiro-cluster/cluster.yaml')); print('YAML válido')"`
Expected: `YAML válido` (usa o módulo `yaml` da biblioteca padrão do Python via PyYAML, já presente no macOS/most dev setups; se o comando falhar por `ModuleNotFoundError: yaml`, rode `pip3 install --user pyyaml` e repita).

- [ ] **Step 3: Criar `01-primeiro-cluster/scripts/create.sh`**

```bash
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
```

- [ ] **Step 4: Criar `01-primeiro-cluster/scripts/destroy.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$DIR/cluster.yaml"

echo "Isso vai destruir o cluster eks-aprendizado-01 e todos os recursos associados (VPC, node group, etc.)."
read -r -p "Digite 'destruir' para confirmar: " CONFIRM

if [ "$CONFIRM" != "destruir" ]; then
  echo "Cancelado."
  exit 1
fi

eksctl delete cluster -f "$CONFIG"
```

- [ ] **Step 5: Tornar os scripts executáveis**

```bash
chmod +x 01-primeiro-cluster/scripts/create.sh 01-primeiro-cluster/scripts/destroy.sh
```

- [ ] **Step 6: Checar sintaxe dos scripts**

Run: `bash -n 01-primeiro-cluster/scripts/create.sh && bash -n 01-primeiro-cluster/scripts/destroy.sh && echo "sintaxe ok"`
Expected: `sintaxe ok`.

- [ ] **Step 7: Validar o `cluster.yaml` com `eksctl --dry-run` (NÃO cria recursos)**

Run: `eksctl create cluster -f 01-primeiro-cluster/cluster.yaml --dry-run`
Expected: uma de duas saídas, ambas aceitáveis:
  - Se houver credenciais AWS válidas: eksctl imprime o `ClusterConfig` resolvido (com defaults preenchidos) e **não** cria nada.
  - Se não houver credenciais (caso deste ambiente): erro relacionado a credenciais/autenticação AWS (ex.: menção a "credentials", "NoCredentialProviders" ou similar).

  Uma falha de **parsing YAML** ou de **schema do eksctl** (ex.: "unknown field", "error unmarshaling") NÃO é aceitável e indica um erro real no `cluster.yaml` que precisa ser corrigido antes de prosseguir.

- [ ] **Step 8: Criar `01-primeiro-cluster/README.md`**

```markdown
# 01 — Primeiro cluster

Objetivo: criar seu primeiro cluster EKS com `eksctl`, entender suas partes,
e destruí-lo com segurança ao terminar.

Pré-requisito: `../00-preparacao/verify.sh` passando sem `FAIL`.

## Conceitos

- **Control plane gerenciado**: a AWS opera o control plane (API server,
  etcd, scheduler) do Kubernetes; você não vê nem gerencia essas máquinas.
  É por isso que ele é cobrado à parte (~US$0,10/h), independente dos nodes.
- **Node group gerenciado**: um grupo de instâncias EC2 (definidas em
  `cluster.yaml`) que a AWS provisiona, atualiza e substitui automaticamente
  em caso de falha, rodando o `kubelet` que se junta ao cluster.
- **VPC**: por padrão, `eksctl` cria uma VPC nova dedicada ao cluster (com
  subnets públicas e privadas), a menos que você aponte para uma existente.

## Passo a passo

1. Reveja `cluster.yaml` — por padrão cria o cluster `eks-aprendizado-01`
   em `us-east-1` com 2 nodes `t3.medium`. Edite `region` se preferir outra
   região.
2. Crie o cluster:

   ```bash
   ./scripts/create.sh
   ```

   Isso demora entre 15 e 20 minutos — o `eksctl` cria a VPC, o control
   plane e o node group nessa ordem.

3. Explore o cluster:

   ```bash
   kubectl cluster-info
   kubectl get nodes -o wide
   kubectl get pods -A
   kubectl describe node <nome-de-um-node>
   ```

   Repare nos pods do namespace `kube-system` (`coredns`, `aws-node`,
   `kube-proxy`) — eles já vêm com o cluster e cuidam de DNS interno e da
   integração de rede com a VPC (`aws-node` é o VPC CNI, que veremos em
   detalhe no módulo 02).

4. Quando terminar de explorar, destrua o cluster para parar de ser
   cobrado:

   ```bash
   ./scripts/destroy.sh
   ```

   Isso também demora alguns minutos. Confirme no console da AWS (EKS e
   EC2) que não sobrou nada rodando.

## Próximo passo

Siga para `02-workloads-networking` (em breve) para aprender a fazer deploy
de aplicações e expô-las via Load Balancer.
```

- [ ] **Step 9: Commit**

```bash
git add 01-primeiro-cluster/
git commit -m "Add module 01-primeiro-cluster: first EKS cluster via eksctl"
```

---

## Fora de escopo deste plano

Módulos 02-workloads-networking, 03-iam-seguranca, 04-observabilidade e
05-scaling-custos serão planejados separadamente quando o usuário chegar
a eles, conforme decidido durante o brainstorming (ver
`docs/superpowers/specs/2026-07-12-eks-aprendizado-design.md`).
