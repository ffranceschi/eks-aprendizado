# 04 — Observabilidade

Objetivo: instrumentar o cluster com duas abordagens complementares:
CloudWatch Container Insights (gerenciado pela AWS) e Prometheus + Grafana
(self-hosted via Helm).

Pré-requisito: `../00-preparacao/verify.sh` passando sem `FAIL`, com
`AWS_PROFILE=ffranceschi-bedrock` exportado (veja
[Conta e profile AWS](../README.md#conta-e-profile-aws) no README raiz).

> Os comandos abaixo seguem o padrão público estável de cada projeto, mas
> não foram exercitados contra um cluster de verdade nesta rodada. Confira
> a doc oficial se algo falhar por versão:
> https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-EKS-addon.html
> e https://github.com/prometheus-community/helm-charts.

## Conceitos

- **CloudWatch Container Insights**: coleta métricas e logs de
  cluster/pods/nodes automaticamente via um add-on gerenciado pela AWS
  (`amazon-cloudwatch-observability`). Custo: cobrado por métrica/log
  ingerido no CloudWatch, sem custo de infraestrutura extra no cluster.
- **Prometheus + Grafana (kube-prometheus-stack)**: roda dentro do próprio
  cluster, sem custo de add-on — mas consome CPU/memória dos seus nodes, e
  por padrão não persiste métricas em armazenamento durável (perde
  histórico se o pod do Prometheus reiniciar, a menos que configure
  `PersistentVolume`).

## Passo a passo

1. Crie o cluster:

   ```bash
   ./scripts/create.sh
   ```

2. **CloudWatch Container Insights** — crie a IAM Role via IRSA e ative o
   add-on:

   ```bash
   export CLUSTER_NAME=eks-aprendizado-04
   export AWS_REGION=us-east-1

   eksctl create iamserviceaccount \
     --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
     --namespace amazon-cloudwatch --name cloudwatch-agent \
     --role-name "AmazonEKSCloudWatchRole-${CLUSTER_NAME}" \
     --attach-policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
     --approve

   aws eks create-addon \
     --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" \
     --addon-name amazon-cloudwatch-observability

   aws eks describe-addon \
     --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" \
     --addon-name amazon-cloudwatch-observability \
     --query "addon.status"
   ```

   Espere o status virar `ACTIVE`, depois veja os dashboards em
   CloudWatch → Container Insights, no console AWS.

3. **Prometheus + Grafana**:

   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo update

   helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
     -n monitoring --create-namespace \
     -f manifests/kube-prometheus-stack-values.yaml
   ```

4. Acesse o Grafana:

   ```bash
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
   ```

   Usuário `admin`, senha:

   ```bash
   kubectl get secret -n monitoring kube-prometheus-stack-grafana \
     -o jsonpath="{.data.admin-password}" | base64 -d
   ```

   Abra `http://localhost:3000` — os dashboards padrão do
   `kube-prometheus-stack` já vêm com visões de cluster, nodes e pods.

5. Limpeza:

   ```bash
   helm uninstall kube-prometheus-stack -n monitoring
   aws eks delete-addon --cluster-name eks-aprendizado-04 --region us-east-1 --addon-name amazon-cloudwatch-observability
   ./scripts/destroy.sh
   ```

## Próximo passo

Siga para [`05-scaling-custos`](../05-scaling-custos/) para Karpenter,
Spot instances, HPA e Fargate.
