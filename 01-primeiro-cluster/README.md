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
