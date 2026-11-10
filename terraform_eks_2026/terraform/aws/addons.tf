# Resolve the addon build that matches this cluster's Kubernetes version
# instead of hardcoding one. The original pinned "v1.25.0-eksbuild.1" against an
# unpinned cluster, which EKS rejects once the default version moves on.
data "aws_eks_addon_version" "this" {
  for_each = toset([
    "vpc-cni",
    "coredns",
    "kube-proxy",
    "aws-ebs-csi-driver",
  ])

  addon_name         = each.value
  kubernetes_version = aws_eks_cluster.cluster.version
  most_recent        = true
}

resource "aws_eks_addon" "core" {
  for_each = toset(["vpc-cni", "coredns", "kube-proxy"])

  cluster_name  = aws_eks_cluster.cluster.name
  addon_name    = each.value
  addon_version = data.aws_eks_addon_version.this[each.value].version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  # coredns cannot schedule until there are nodes to run on.
  depends_on = [aws_eks_node_group.private]
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.cluster.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = data.aws_eks_addon_version.this["aws-ebs-csi-driver"].version
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.private]
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust["ebs-csi-controller-sa"].json
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
