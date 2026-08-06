# The original config built IAM roles for these two controllers but never
# installed the controllers themselves, so every ALB Ingress in
# kubernetes/manifests/ stayed unfulfilled.

resource "helm_release" "aws_load_balancer_controller" {
  count = var.install_helm_releases ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.alb_controller_chart_version

  set = [
    {
      name  = "clusterName"
      value = aws_eks_cluster.cluster.name
    },
    {
      name  = "region"
      value = var.region
    },
    {
      name  = "vpcId"
      value = aws_vpc.vpc.id
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.aws_load_balancer_controller.arn
    },
  ]

  depends_on = [
    aws_iam_role_policy_attachment.aws_load_balancer_controller,
    aws_eks_node_group.private,
    aws_eks_addon.core,
  ]
}

resource "helm_release" "cluster_autoscaler" {
  count = var.install_helm_releases ? 1 : 0

  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = var.cluster_autoscaler_chart_version

  # The chart selects an image matching the cluster version, which removes the
  # manual image-tag/K8s-version pairing the old manifest got wrong.
  set = [
    {
      name  = "autoDiscovery.clusterName"
      value = aws_eks_cluster.cluster.name
    },
    {
      name  = "awsRegion"
      value = var.region
    },
    {
      name  = "rbac.serviceAccount.create"
      value = "true"
    },
    {
      name  = "rbac.serviceAccount.name"
      value = "cluster-autoscaler"
    },
    {
      name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.cluster_autoscaler.arn
    },
    {
      name  = "extraArgs.balance-similar-node-groups"
      value = "true"
    },
    {
      name  = "extraArgs.skip-nodes-with-system-pods"
      value = "false"
    },
  ]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_autoscaler,
    aws_autoscaling_group_tag.autoscaler_enabled,
    aws_autoscaling_group_tag.autoscaler_cluster,
    aws_eks_addon.core,
  ]
}
