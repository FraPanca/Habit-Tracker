resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.9.2"
  namespace        = "argocd"
  create_namespace = true

  depends_on = [
    aws_eks_node_group.default,
    aws_eks_access_entry.admin,
    aws_eks_access_policy_association.admin,
  ]
}