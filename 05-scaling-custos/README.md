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
> `KARPENTER_VERSION` conforme a doc oficial. Não foi exercitado contra um
> cluster de verdade nesta rodada.

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
  usando o `metrics-server` (já incluído por padrão em clusters EKS
  gerenciados).
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
   export KARPENTER_VERSION="1.1.1"  # confira a versão mais recente antes de usar

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
     --namespace kube-system --name karpenter \
     --role-name "KarpenterControllerRole-${CLUSTER_NAME}" \
     --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}" \
     --approve
   ```

4. Instale o Karpenter via Helm:

   ```bash
   helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
     --version "${KARPENTER_VERSION}" \
     --namespace kube-system \
     --set settings.clusterName="$CLUSTER_NAME" \
     --set settings.interruptionQueue="$CLUSTER_NAME" \
     --wait
   ```

5. Aplique o `NodePool`/`EC2NodeClass` e gere carga para ver o Karpenter
   provisionar node novo:

   ```bash
   kubectl apply -f manifests/karpenter-nodepool.yaml

   kubectl create deployment inflate --image=public.ecr.aws/eks-distro/kubernetes/pause:3.7
   kubectl scale deployment inflate --replicas=5

   kubectl get nodes -w
   # espere aparecer um node novo com label karpenter.sh/capacity-type=spot

   kubectl get nodeclaims
   ```

6. **HPA**: aplique o deployment com carga de CPU e observe o número de
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
   ./scripts/destroy.sh
   ```

## Próximo passo

Você completou os módulos planejados até aqui. Próximos temas possíveis:
CI/CD e GitOps (ArgoCD/Flux), multi-cluster, ou aprofundar qualquer um dos
módulos anteriores.
