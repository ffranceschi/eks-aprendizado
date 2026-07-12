# 01 — Primeiro cluster

Objetivo: criar seu primeiro cluster EKS com `eksctl`, entender suas partes,
e destruí-lo com segurança ao terminar.

Pré-requisito: `../00-preparacao/verify.sh` passando sem `FAIL`, com
`AWS_PROFILE=ffranceschi-bedrock` exportado (veja
[Conta e profile AWS](../README.md#conta-e-profile-aws) no README raiz).

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

4. Bônus — descubra qual instância está respondendo: faça o deploy de um
   nginx com 2 réplicas (uma em cada node, via `podAntiAffinity`), onde cada
   réplica serve uma página HTML mostrando o nome do node (a instância EC2)
   que a está rodando. O nome do node vem da
   [Downward API](https://kubernetes.io/docs/concepts/workloads/pods/downward-api/)
   (`fieldRef: spec.nodeName`) — o kubelet injeta esse valor como variável de
   ambiente no container, sem nenhuma chamada de rede extra.

   ```bash
   kubectl apply -f manifests/nginx-node-demo.yaml
   kubectl rollout status deployment/nginx-node-demo
   kubectl get pods -l app=nginx-node-demo -o wide
   ```

   Confirme que as duas réplicas caíram em nodes diferentes (coluna `NODE`).

   Para acessar a página do seu terminal, use `port-forward`:

   ```bash
   kubectl port-forward svc/nginx-node-demo 8080:80
   ```

   E em outro terminal:

   ```bash
   curl http://localhost:8080/
   ```

   **Atenção**: `kubectl port-forward` para um Service prende a conexão a
   **uma única pod** durante toda a sessão — ele não balanceia entre as
   réplicas. Rodar `curl` várias vezes vai sempre mostrar o mesmo node. Isso
   é uma particularidade do `port-forward` (ele resolve o Service para um
   pod só uma vez), não de como o Service funciona de verdade dentro do
   cluster.

   Para ver o balanceamento de verdade entre os nodes, curle o Service de
   **dentro** do cluster, onde o `kube-proxy` decide o destino a cada nova
   conexão:

   ```bash
   kubectl run curltest --image=curlimages/curl:8.10.1 --restart=Never --rm -i --command -- \
     sh -c 'for i in 1 2 3 4 5 6; do curl -s http://nginx-node-demo/ | grep "Node ("; done'
   ```

   Aqui as respostas alternam entre os dois nodes — é o Service (`ClusterIP`)
   distribuindo as requisições entre as réplicas via `kube-proxy`. O
   [módulo 02](../02-workloads-networking) explica Services e Ingress em
   profundidade.

   Limpe os recursos de teste quando terminar (o cluster continua no ar):

   ```bash
   kubectl delete -f manifests/nginx-node-demo.yaml
   ```

5. Quando terminar de explorar, destrua o cluster para parar de ser
   cobrado:

   ```bash
   ./scripts/destroy.sh
   ```

   Isso também demora alguns minutos. Confirme no console da AWS (EKS e
   EC2) que não sobrou nada rodando.

## Próximo passo

Siga para `02-workloads-networking` (em breve) para aprender a fazer deploy
de aplicações e expô-las via Load Balancer.
