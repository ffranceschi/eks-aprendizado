# 02 — Workloads e networking

Objetivo: fazer deploy de uma aplicação com config via `ConfigMap`/`Secret`,
entender `Service` (`ClusterIP`), e expô-la publicamente de verdade via
`Ingress` + AWS Load Balancer Controller.

Pré-requisito: `../00-preparacao/verify.sh` passando sem `FAIL`, com
`AWS_PROFILE=ffranceschi-bedrock` exportado (veja
[Conta e profile AWS](../README.md#conta-e-profile-aws) no README raiz).

> Os comandos de instalação do AWS Load Balancer Controller abaixo seguem o
> padrão público estável do projeto, mas não foram exercitados contra um
> cluster de verdade nesta rodada. Se algum comando falhar por versão,
> confira a doc oficial:
> https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/

## Conceitos

- **ConfigMap vs Secret**: ambos guardam configuração fora da imagem do
  container; a diferença é convenção de uso (Secret para dados sensíveis) —
  o Kubernetes não criptografa Secrets no `etcd` por padrão, então isso não
  substitui um cofre de segredos real (veremos AWS Secrets Manager no
  módulo 03).
- **Service `ClusterIP`**: IP interno estável que balanceia entre as pods
  do Deployment, resolvido via DNS interno (`coredns`) como
  `<nome>.<namespace>.svc.cluster.local`.
- **VPC CNI**: no EKS, cada pod recebe um IP real dentro da VPC (não uma
  rede overlay separada) — é por isso que o `aws-node` (VPC CNI) aparece em
  todo node.
- **Ingress + AWS Load Balancer Controller**: o `Ingress` é só a
  especificação de roteamento; quem efetivamente provisiona um Application
  Load Balancer real na AWS é o controller, que fica de olho nos objetos
  `Ingress` do cluster via IRSA.

## Passo a passo

1. Crie o cluster:

   ```bash
   ./scripts/create.sh
   ```

2. Aplique a aplicação de exemplo:

   ```bash
   kubectl apply -f manifests/app.yaml
   kubectl rollout status deployment/app-modulo02
   ```

3. Confirme que a Secret chegou como variável de ambiente e o ConfigMap
   como arquivo:

   ```bash
   POD=$(kubectl get pods -l app=app-modulo02 -o jsonpath='{.items[0].metadata.name}')
   kubectl exec "$POD" -- printenv MENSAGEM_SECRETA
   kubectl exec "$POD" -- cat /usr/share/nginx/html/index.html
   ```

4. Repare que os IPs das pods estão dentro do CIDR da VPC do cluster
   (mesmo padrão `192.168.0.0/16` do módulo 01):

   ```bash
   kubectl get pods -l app=app-modulo02 -o wide
   ```

5. Instale o AWS Load Balancer Controller (via IRSA + Helm):

   ```bash
   export CLUSTER_NAME=eks-aprendizado-02
   export AWS_REGION=us-east-1
   export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   export VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.resourcesVpcConfig.vpcId" --output text)

   curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json

   aws iam create-policy \
     --policy-name "AWSLoadBalancerControllerIAMPolicy-${CLUSTER_NAME}" \
     --policy-document file://iam_policy.json

   eksctl create iamserviceaccount \
     --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
     --namespace kube-system --name aws-load-balancer-controller \
     --role-name "AmazonEKSLoadBalancerControllerRole-${CLUSTER_NAME}" \
     --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy-${CLUSTER_NAME}" \
     --approve

   helm repo add eks https://aws.github.io/eks-charts
   helm repo update

   helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
     -n kube-system \
     --set clusterName="$CLUSTER_NAME" \
     --set serviceAccount.create=false \
     --set serviceAccount.name=aws-load-balancer-controller \
     --set region="$AWS_REGION" \
     --set vpcId="$VPC_ID"
   ```

6. Aplique o `Ingress` e aguarde o ALB ficar pronto (pode levar alguns
   minutos):

   ```bash
   kubectl apply -f manifests/ingress.yaml
   kubectl get ingress app-modulo02 -w
   ```

   Quando a coluna `ADDRESS` mostrar um DNS (`*.elb.amazonaws.com`), acesse
   no navegador ou:

   ```bash
   curl "http://$(kubectl get ingress app-modulo02 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
   ```

7. Limpeza, **nesta ordem** (o Ingress precisa sair primeiro para o
   controller desprovisionar o ALB):

   ```bash
   kubectl delete -f manifests/ingress.yaml
   kubectl delete -f manifests/app.yaml
   ./scripts/destroy.sh
   ```

## Próximo passo

Siga para [`03-iam-seguranca`](../03-iam-seguranca/) para aprofundar RBAC,
Pod Security Standards e IRSA.
