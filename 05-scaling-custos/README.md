# 05 — Scaling e custos

Objetivo: usar Karpenter para provisionar nodes sob demanda (priorizando
Spot), escalar pods automaticamente com HPA, e rodar workloads sem node
nenhum via Fargate — as três ferramentas centrais de otimização de custo
no EKS.

Pré-requisito: `../00-preparacao/verify.sh` passando sem `FAIL`, com
`AWS_PROFILE=ffranceschi-bedrock` exportado (veja
[Conta e profile AWS](../README.md#conta-e-profile-aws) no README raiz).

> A instalação do Karpenter abaixo segue o guia oficial
> (https://karpenter.sh/docs/getting-started/), mas envolve várias peças
> (CloudFormation, IAM, Helm) que evoluem com frequência — confira sempre a
> versão mais recente do Karpenter antes de rodar, e ajuste
> `KARPENTER_VERSION` conforme a doc oficial. O Karpenter é a única parte
> deste projeto provisionada via CloudFormation (para as IAM Roles) — é uma
> exceção consciente ao padrão eksctl/Helm do restante do repositório,
> seguindo o guia oficial do Karpenter.
>
> Exercitado de ponta a ponta contra um cluster real com Karpenter 1.14.0
> (2026-07-18). Três problemas foram encontrados e corrigidos no passo a
> passo abaixo e nos manifests — se você usar uma versão diferente, fique
> atento a regressões parecidas:
> 1. O template CloudFormation do Karpenter v1.x não cria mais uma role de
>    controller única, só policies granulares (ver nota no passo 3).
> 2. `EC2NodeClass.spec.amiSelectorTerms` é obrigatório (`amiFamily` sozinho
>    não basta) — o manifest usa `alias: al2023@latest`.
> 3. A AMI AL2023 vem com swap (zram) habilitado, e o kubelet recusa subir
>    com swap ligado — o manifest injeta `userData` com
>    `--fail-swap-on=false`. Sem isso, os nodes provisionados pelo Karpenter
>    nunca se registram no cluster (ficam presos, EC2 rodando mas sem
>    aparecer em `kubectl get nodes`).

## Conceitos

- **Karpenter**: observa pods `Pending` (sem node onde caber) e provisiona
  instâncias EC2 sob demanda — mais rápido e flexível que o Cluster
  Autoscaler tradicional, que só escala node groups pré-definidos.
  Também **consolida** nodes subutilizados automaticamente, terminando-os
  para economizar.
- **Spot instances**: até ~70% mais baratas que on-demand, mas a AWS pode
  interromper com ~2 minutos de aviso. Bom para workloads tolerantes a
  interrupção (stateless, com múltiplas réplicas).
- **HPA (Horizontal Pod Autoscaler)**: escala o número de réplicas de um
  Deployment com base em métricas (CPU, memória, ou métricas customizadas),
  usando o `metrics-server`. Nem sempre vem instalado por padrão — depende
  da versão do `eksctl`/EKS (algumas já o instalam como add-on gerenciado);
  confira antes de instalar manualmente (veja o passo 6).
- **Fargate profiles**: rodam pods sem node EC2 gerenciado por você —
  cobrado por pod (vCPU/memória solicitados), sem overhead de gerenciar
  instâncias.

## Passo a passo

1. Crie o cluster (nodegroup de bootstrap pequeno, 1x `t3.small`):

   ```bash
   ./scripts/create.sh
   ```

2. Configure variáveis e faça o tagging de discovery do Karpenter nas
   subnets e no security group do cluster:

   ```bash
   export CLUSTER_NAME=eks-aprendizado-05
   export AWS_REGION=us-east-1
   export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   export KARPENTER_VERSION="1.14.0"  # confira a versão mais recente antes de usar

   VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.resourcesVpcConfig.vpcId" --output text)

   SUBNET_IDS=$(aws ec2 describe-subnets --region "$AWS_REGION" \
     --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
     --query "Subnets[].SubnetId" --output text)
   for SUBNET in $SUBNET_IDS; do
     aws ec2 create-tags --region "$AWS_REGION" --resources "$SUBNET" --tags Key=karpenter.sh/discovery,Value="$CLUSTER_NAME"
   done

   CLUSTER_SG_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)
   aws ec2 create-tags --region "$AWS_REGION" --resources "$CLUSTER_SG_ID" --tags Key=karpenter.sh/discovery,Value="$CLUSTER_NAME"
   ```

3. Crie as IAM Roles do Karpenter via o template CloudFormation oficial:

   ```bash
   curl -fsSL "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml" > /tmp/karpenter-cfn.yaml

   aws cloudformation deploy \
     --stack-name "Karpenter-${CLUSTER_NAME}" \
     --template-file /tmp/karpenter-cfn.yaml \
     --capabilities CAPABILITY_NAMED_IAM \
     --parameter-overrides "ClusterName=${CLUSTER_NAME}" \
     --region "$AWS_REGION"

   eksctl create iamidentitymapping \
     --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
     --arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}" \
     --username system:node:{{EC2PrivateDNSName}} \
     --group system:bootstrappers \
     --group system:nodes

   eksctl create iamserviceaccount \
     --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
     --name karpenter --namespace kube-system \
     --role-name "KarpenterControllerRole-${CLUSTER_NAME}" \
     --role-only \
     --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerNodeLifecyclePolicy-${CLUSTER_NAME}" \
     --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerIAMIntegrationPolicy-${CLUSTER_NAME}" \
     --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerEKSIntegrationPolicy-${CLUSTER_NAME}" \
     --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerInterruptionPolicy-${CLUSTER_NAME}" \
     --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerResourceDiscoveryPolicy-${CLUSTER_NAME}" \
     --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerZonalShiftPolicy-${CLUSTER_NAME}" \
     --approve
   ```

   > A partir da v1.x, o template CloudFormation do Karpenter não cria mais
   > uma `KarpenterControllerPolicy` única — ele cria 6 policies granulares
   > (`NodeLifecyclePolicy`, `IAMIntegrationPolicy`, `EKSIntegrationPolicy`,
   > `InterruptionPolicy`, `ResourceDiscoveryPolicy`, `ZonalShiftPolicy`). A
   > role do controller precisa ser criada à parte com todas elas anexadas —
   > por isso o `eksctl create iamserviceaccount` acima. Use sempre
   > `--role-only`: sem essa flag o eksctl também cria/gerencia o
   > ServiceAccount do Kubernetes, e o `helm install` do passo 4 (que tem
   > `serviceAccount.create=true` por padrão) sobrescreve as annotations de
   > IRSA nele — o controller acaba assumindo a role do node (via IMDS) em
   > vez da `KarpenterControllerRole`, o que causa `UnauthorizedOperation`
   > (ex.: `ec2:DescribeInstanceTypeOfferings`) e `CrashLoopBackOff`.

4. Instale o Karpenter via Helm, passando a role-arn criada no passo 3
   diretamente na annotation do ServiceAccount (é o Helm quem cria o objeto
   `ServiceAccount` de fato, já que usamos `--role-only` acima) e
   `replicas=1` (o node group de bootstrap tem só 1 node — com o padrão de 2
   réplicas e anti-affinity entre pods, o segundo Karpenter fica `Pending`
   para sempre e o `--wait` estoura o timeout):

   ```bash
   helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
     --version "${KARPENTER_VERSION}" \
     --namespace kube-system \
     --set settings.clusterName="$CLUSTER_NAME" \
     --set settings.interruptionQueue="$CLUSTER_NAME" \
     --set replicas=1 \
     --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterControllerRole-${CLUSTER_NAME}" \
     --wait
   ```

   Se um `helm install` anterior tiver falhado (release em estado `failed`
   bloqueia reinstalação com "cannot reuse a name that is still in use"),
   rode `helm uninstall karpenter -n kube-system` antes de tentar de novo.

5. Aplique o `NodePool`/`EC2NodeClass` e gere carga para ver o Karpenter
   provisionar node novo:

   ```bash
   kubectl apply -f manifests/karpenter-nodepool.yaml

   kubectl create deployment inflate --image=public.ecr.aws/eks-distro/kubernetes/pause:3.7
   kubectl scale deployment inflate --replicas=5

   kubectl get nodes -w
   # espere aparecer um node novo — label karpenter.sh/capacity-type=spot ou
   # on-demand (veja nota abaixo sobre por que pode vir on-demand)

   kubectl get nodeclaims
   ```

   > Se sua conta AWS nunca usou Spot, a primeira tentativa de capacidade
   > Spot falha com `AuthFailure.ServiceLinkedRoleCreationNotPermitted`
   > (falta a service-linked role `AWSServiceRoleForEC2Spot`) e o Karpenter
   > cai automaticamente para on-demand — o `NodePool` aceita os dois. Para
   > habilitar Spot de fato, crie a role uma vez:
   > `aws iam create-service-linked-role --aws-service-name spot.amazonaws.com`
   > (ignore o erro se ela já existir).
   >
   > O `NodePool` também exclui os tamanhos `nano`/`micro` de propósito: são
   > baratos, mas o limite de pods por ENI nessas instâncias mal cobre os
   > daemonsets do sistema (`aws-node`, `kube-proxy`), então o Karpenter
   > cria node atrás de node sem nunca caber o pod da carga — um loop caro
   > e silencioso se você remover esse filtro.

6. **HPA**: confirme se o `metrics-server` (pré-requisito do HPA) já está
   instalado antes de aplicar o manifest — versões recentes do `eksctl`
   instalam `metrics-server` como **EKS add-on gerenciado** por padrão
   (`aws eks list-addons --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"`).
   Só rode o `kubectl apply` abaixo se ele **não** aparecer nessa lista:

   ```bash
   kubectl get deployment metrics-server -n kube-system 2>/dev/null \
     || kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

   kubectl wait --for=condition=Available deployment/metrics-server -n kube-system --timeout=90s
   kubectl top nodes
   ```

   > Se você aplicar o manifest por cima do add-on já existente, o `Service`
   > é mesclado com um `selector` que exige o label `k8s-app=metrics-server`
   > — label que os pods do add-on gerenciado **não têm** (eles usam
   > `app.kubernetes.io/name=metrics-server`). Isso zera os endpoints do
   > Service e `kubectl top nodes` passa a falhar com "Metrics API not
   > available", mesmo com os pods `Running`. Se isso acontecer, remova o
   > `k8s-app` do selector:
   > `kubectl patch svc metrics-server -n kube-system --type=json -p='[{"op":"remove","path":"/spec/selector/k8s-app"}]'`

   Agora aplique o deployment com carga de CPU e observe o número de
   réplicas subir:

   ```bash
   kubectl apply -f manifests/hpa-demo.yaml
   kubectl get hpa carga-cpu -w
   ```

7. **Fargate profile**: rode um pod sem node EC2 nenhum:

   ```bash
   eksctl create fargateprofile \
     --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
     --name fp-modulo05 \
     --namespace fargate-demo

   kubectl create namespace fargate-demo
   kubectl -n fargate-demo run nginx-fargate --image=nginx:1.27-alpine
   kubectl -n fargate-demo get pods -o wide
   # o node listado é um node "virtual" do Fargate, não uma das suas EC2
   ```

8. **Custo — resumo**:

   | Opção | Custo relativo | Quando usar |
   |---|---|---|
   | On-demand | referência (100%) | workloads que não toleram interrupção |
   | Spot | ~30% do on-demand | workloads stateless, tolerantes a interrupção com aviso de 2min |
   | Fargate | cobrado por pod (vCPU/mem solicitados) | workloads esporádicos, sem querer gerenciar nodes |
   | Karpenter (consolidação) | reduz desperdício em qualquer um dos acima | sempre, quando não estiver usando só Fargate |

9. Limpeza, **nesta ordem**:

   ```bash
   kubectl delete -f manifests/hpa-demo.yaml
   kubectl delete deployment inflate
   kubectl delete -f manifests/karpenter-nodepool.yaml
   kubectl delete namespace fargate-demo
   eksctl delete fargateprofile --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --name fp-modulo05
   helm uninstall karpenter -n kube-system
   aws cloudformation delete-stack --stack-name "Karpenter-${CLUSTER_NAME}" --region "$AWS_REGION"
   aws iam detach-role-policy --role-name "KarpenterControllerRole-${CLUSTER_NAME}" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerNodeLifecyclePolicy-${CLUSTER_NAME}"
   aws iam detach-role-policy --role-name "KarpenterControllerRole-${CLUSTER_NAME}" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerIAMIntegrationPolicy-${CLUSTER_NAME}"
   aws iam detach-role-policy --role-name "KarpenterControllerRole-${CLUSTER_NAME}" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerEKSIntegrationPolicy-${CLUSTER_NAME}"
   aws iam detach-role-policy --role-name "KarpenterControllerRole-${CLUSTER_NAME}" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerInterruptionPolicy-${CLUSTER_NAME}"
   aws iam detach-role-policy --role-name "KarpenterControllerRole-${CLUSTER_NAME}" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerResourceDiscoveryPolicy-${CLUSTER_NAME}"
   aws iam detach-role-policy --role-name "KarpenterControllerRole-${CLUSTER_NAME}" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerZonalShiftPolicy-${CLUSTER_NAME}"
   aws iam delete-role --role-name "KarpenterControllerRole-${CLUSTER_NAME}"
   ./scripts/destroy.sh
   ```

   > A role `KarpenterControllerRole-${CLUSTER_NAME}` foi criada no passo 3
   > com `eksctl create iamserviceaccount --role-only`, fora do stack
   > CloudFormation — por isso precisa ser removida manualmente aqui antes
   > do `delete-stack` (que apaga as policies) e do `destroy.sh`.

## Próximo passo

Você completou os módulos planejados até aqui. Próximos temas possíveis:
CI/CD e GitOps (ArgoCD/Flux), multi-cluster, ou aprofundar qualquer um dos
módulos anteriores.
