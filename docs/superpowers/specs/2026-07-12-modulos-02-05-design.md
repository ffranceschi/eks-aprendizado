# Design: Módulos 02-05 (workloads/networking, IAM, observabilidade, scaling/custos)

Data: 2026-07-12

## Contexto

Complementa `docs/superpowers/specs/2026-07-12-eks-aprendizado-design.md`, que já
define a estrutura geral do projeto e um esboço de conteúdo por módulo. Este
documento fecha as decisões técnicas concretas para os módulos 02 a 05, que
ainda não tinham sido detalhadas.

## Decisão de escopo desta rodada

Os módulos serão **escritos e validados estaticamente** (sintaxe de shell,
parse de YAML, `eksctl --dry-run` quando aplicável) mas **sem criar clusters
reais agora**. O usuário vai rodar cada módulo no seu próprio ritmo depois,
como fez no módulo 01. Isso significa que os comandos abaixo seguem padrões
estáveis e documentados publicamente pela AWS/Karpenter/Helm, mas não foram
exercitados contra um cluster de verdade nesta rodada — cada README deve
deixar isso implícito ao ser um guia didático, não uma alegação de "testado
agora".

## Convenção compartilhada (reforça o design original)

- Cada módulo tem seu próprio `cluster.yaml` com nome de cluster distinto
  (`eks-aprendizado-0N`), sem reaproveitar cluster de módulo anterior.
- `scripts/create.sh` / `scripts/destroy.sh` seguem o mesmo padrão do módulo
  01: `set -euo pipefail`, resolução de diretório via `BASH_SOURCE`,
  confirmação digitada (`criar` / `destruir`) antes de agir.
- Módulos que precisam de IRSA habilitam OIDC no `cluster.yaml` via:
  ```yaml
  iam:
    withOIDC: true
  ```

## Módulo 02 — workloads-networking

**Cluster:** `eks-aprendizado-02`, `iam.withOIDC: true` (necessário para o
AWS Load Balancer Controller via IRSA).

**Conteúdo:**
1. Deployment de uma app simples (reaproveita o padrão nginx do módulo 01)
   lendo conteúdo de um `ConfigMap` montado como volume, e uma `Secret`
   nativa (valor de exemplo, não sensível) consumida via variável de
   ambiente — para ensinar as duas formas de injeção de configuração.
2. `Service` tipo `ClusterIP` (baseline) e menção conceitual a `NodePort`
   (sem expor de verdade — exigiria abrir Security Group manualmente, fora
   do escopo).
3. **AWS Load Balancer Controller**: instalado via Helm, autenticado via
   IRSA (`eksctl create iamserviceaccount` + policy IAM oficial da AWS).
   Cria um `Ingress` (`ingressClassName: alb`) que provisiona um ALB
   público de verdade — é aqui que a app fica acessível externamente.
4. Nota sobre VPC CNI: `kubectl get pods -o wide` mostra IPs de pod dentro
   do CIDR da VPC do cluster (mesmo padrão `192.168.0.0/16` do módulo 01),
   diferente de outros CNIs que usam uma rede overlay separada.

**Ordem de limpeza:** deletar o `Ingress` primeiro (libera o ALB) antes de
destruir o cluster — senão o `eksctl delete` pode deixar o ALB órfão.

## Módulo 03 — iam-seguranca

**Cluster:** `eks-aprendizado-03`, `iam.withOIDC: true`.

**Conteúdo:**
1. **RBAC**: namespace `equipe-dev`, uma `Role` restrita a
   `get/list/watch` em `pods` e `pods/log` nesse namespace, `RoleBinding`
   para um usuário fictício. Demonstração com
   `kubectl auth can-i --as=<user> <verbo> <recurso> -n equipe-dev`.
2. **Pod Security Standards**: label
   `pod-security.kubernetes.io/enforce=restricted` num namespace, mostrando
   um pod privilegiado sendo rejeitado pelo admission controller e um pod
   "compliant" sendo aceito.
3. **IRSA na prática** (aprofunda o que módulo 02 usou para o LB
   Controller): cria uma IAM Role com trust policy escopada a uma
   `ServiceAccount` específica (via `eksctl create iamserviceaccount`) com
   uma policy mínima (ex.: `s3:ListBucket` num bucket específico, ou
   simplesmente permissão de `sts:GetCallerIdentity`, que já basta para
   provar a identidade assumida). Um pod usando essa `ServiceAccount` roda
   `aws sts get-caller-identity` e mostra que assume a IAM Role da SA, não
   a IAM Role do node.
4. **Secrets**: nota curta (seção "avançado, opcional") sobre o padrão
   External Secrets Operator + AWS Secrets Manager, sem implementar de
   ponta a ponta (exigiria um secret pré-criado no Secrets Manager, fora do
   escopo de um guia autocontido).

## Módulo 04 — observabilidade

**Cluster:** `eks-aprendizado-04`.

**Conteúdo:**
1. **CloudWatch Container Insights**: habilitado via o EKS add-on gerenciado
   `amazon-cloudwatch-observability` (substituiu o setup manual antigo de
   DaemonSet do CloudWatch Agent + Fluent Bit). Requer uma IAM Role para o
   add-on (policy `CloudWatchAgentServerPolicy`), criada via
   `eksctl create iamserviceaccount` do mesmo jeito que os módulos
   anteriores.
2. **Prometheus + Grafana**: chart Helm `kube-prometheus-stack`
   (repositório `prometheus-community`), instalado com valores mínimos.
   Acesso ao Grafana via `kubectl port-forward` (mesma ressalva do módulo
   01 sobre port-forward não balancear entre réplicas — aqui não é
   problema pois o Grafana roda com 1 réplica por padrão).
3. Comparação rápida: Container Insights (gerenciado, custo por métrica
   ingerida) vs. Prometheus/Grafana self-hosted (sem custo de add-on, mas
   consome recursos do próprio cluster e não persiste dados sem
   configuração extra).

## Módulo 05 — scaling-custos

**Cluster:** `eks-aprendizado-05`, com um managed node group **pequeno**
(1 node `t3.small`) só para bootstrap — o Karpenter assume o provisionamento
dos nodes de carga de trabalho depois disso.

**Conteúdo:**
1. **Karpenter**: instalação seguindo o guia oficial getting-started (IAM
   roles via CloudFormation/eksctl, tags de discovery em subnets/security
   groups, `helm install karpenter` a partir do OCI registry oficial). Cria
   um `NodePool` + `EC2NodeClass` configurados com
   `capacity-type: [spot, on-demand]` priorizando spot, para provisionar
   nodes sob demanda conforme pods pendentes aparecem.
2. **HPA**: `HorizontalPodAutoscaler` baseado em CPU sobre um Deployment de
   teste (usa o `metrics-server`, que já vem instalado por padrão em
   clusters EKS gerenciados desde 2024).
3. **Fargate profile**: `eksctl create fargateprofile` para um namespace
   específico, mostrando pods rodando sem node EC2 nenhum.
4. **Discussão de custo**: tabela comparando on-demand vs. spot (~70%
   mais barato, risco de interrupção com aviso de 2 minutos) vs. Fargate
   (cobrado por pod, sem gestão de node) — e como o Karpenter consolida
   nodes subutilizados automaticamente para reduzir desperdício.

## Fora de escopo (mantido do design original)

CI/CD e GitOps, Terraform/CDK, multi-cluster/multi-região/DR.

## Critério de conclusão desta rodada

Cada módulo é considerado "escrito" quando README + `cluster.yaml` +
scripts + manifests existem, passam validação estática (sintaxe de shell,
parse de YAML, `eksctl --dry-run` quando aplicável), e o README deixa claro
que a criação real do cluster é uma ação manual e cobrada, a ser feita pelo
usuário quando ele decidir estudar aquele módulo.
