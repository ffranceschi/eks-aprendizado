# 03 — IAM e segurança

Objetivo: praticar RBAC, Pod Security Standards e IRSA — os três
mecanismos de controle de acesso mais usados no dia a dia de um cluster
EKS.

Pré-requisito: `../00-preparacao/verify.sh` passando sem `FAIL`, com
`AWS_PROFILE=ffranceschi-bedrock` exportado (veja
[Conta e profile AWS](../README.md#conta-e-profile-aws) no README raiz).

## Conceitos

- **RBAC**: controla o que uma identidade (usuário, grupo ou
  ServiceAccount) pode fazer **dentro** do Kubernetes (ex.: ler pods num
  namespace). É ortogonal ao IAM da AWS.
- **Pod Security Standards (PSS)**: substituíram o antigo `PodSecurityPolicy`
  (removido do Kubernetes). São aplicados via label no namespace
  (`restricted`, `baseline` ou `privileged`) e bloqueiam pods que não
  cumprem o nível escolhido, via admission controller nativo — sem precisar
  instalar nada.
- **IRSA (IAM Roles for Service Accounts)**: permite que um pod específico
  assuma uma IAM Role da AWS via sua `ServiceAccount`, em vez de herdar a
  IAM Role do node (que normalmente é ampla demais). Já usamos isso no
  módulo 02 para o Load Balancer Controller — aqui vemos o mecanismo por
  trás.

## Passo a passo

1. Crie o cluster:

   ```bash
   ./scripts/create.sh
   ```

2. **RBAC** — aplique e teste permissões:

   ```bash
   kubectl apply -f manifests/rbac.yaml

   kubectl auth can-i list pods -n equipe-dev --as=dev-fulano
   # yes

   kubectl auth can-i delete pods -n equipe-dev --as=dev-fulano
   # no
   ```

3. **Pod Security Standards** — aplique o namespace + pod compliant, depois
   tente o pod privilegiado:

   ```bash
   kubectl apply -f manifests/pod-security-demo.yaml
   kubectl get pods -n seguro
   # pod-compliant deve estar Running

   kubectl apply -f manifests/pod-privilegiado-rejeitado.yaml
   # esperado: erro do admission controller recusando o pod
   # (violates PodSecurity "restricted:latest": privileged ...)
   ```

4. **IRSA na prática** — crie uma IAM Role escopada à ServiceAccount e prove
   que o pod assume essa role (não a do node):

   ```bash
   export CLUSTER_NAME=eks-aprendizado-03
   export AWS_REGION=us-east-1

   eksctl create iamserviceaccount \
     --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
     --namespace default --name irsa-demo \
     --role-name "IrsaDemoRole-${CLUSTER_NAME}" \
     --attach-policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess \
     --approve

   kubectl apply -f manifests/irsa-demo-pod.yaml
   kubectl wait --for=condition=Ready pod/irsa-demo --timeout=60s

   kubectl exec -it irsa-demo -- aws sts get-caller-identity
   ```

   Repare que o `Arn` retornado é o da `IrsaDemoRole-eks-aprendizado-03`,
   não a IAM Role do node (`eksctl-eks-aprendizado-03-...-NodeInstanceRole`).
   Isso é o que torna o IRSA mais seguro que dar a IAM Role do node acesso
   amplo a tudo que qualquer pod naquele node possa precisar.

   > Usamos `arn:aws:iam::aws:policy/ReadOnlyAccess` só para a demonstração
   > ser simples de reproduzir. Em uso real, escreva uma policy do tamanho
   > exato do que o pod precisa (ex.: `s3:GetObject` num bucket específico).

5. **Secrets (avançado, opcional)**: Secrets nativas do Kubernetes não são
   criptografadas no `etcd` por padrão. Para segredos de verdade (senhas de
   banco, API keys), o padrão mais usado com EKS é o
   [External Secrets Operator](https://external-secrets.io/) sincronizando
   valores do AWS Secrets Manager para dentro do cluster como Secrets
   nativas — o operator lê do Secrets Manager via IRSA (mesmo mecanismo do
   passo 4) e mantém a Secret do Kubernetes atualizada. Não implementamos
   isso de ponta a ponta aqui porque exigiria um secret pré-criado no
   Secrets Manager fora do escopo deste guia autocontido — mas vale
   explorar por conta própria se for usar Secrets Manager no seu trabalho.

6. Limpeza:

   ```bash
   kubectl delete -f manifests/irsa-demo-pod.yaml
   eksctl delete iamserviceaccount --cluster eks-aprendizado-03 --region us-east-1 --namespace default --name irsa-demo
   ./scripts/destroy.sh
   ```

## Próximo passo

Siga para [`04-observabilidade`](../04-observabilidade/) para instrumentar
o cluster com métricas e logs.
