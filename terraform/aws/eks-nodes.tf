data "aws_iam_policy_document" "nodes_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nodes" {
  name               = "${var.cluster_name}-nodes"
  assume_role_policy = data.aws_iam_policy_document.nodes_assume_role.json
}

resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])

  policy_arn = each.value
  role       = aws_iam_role.nodes.name
}

resource "aws_eks_node_group" "private" {
  for_each = local.private_subnets

  cluster_name    = aws_eks_cluster.cluster.name
  node_group_name = "priv-nodes-${each.key}"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = [aws_subnet.private[each.key].id]

  # Amazon Linux 2 reached end of support for EKS AMIs; AL2023 is current.
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = var.node_instance_types

  scaling_config {
    min_size     = var.node_group_scaling.min_size
    max_size     = var.node_group_scaling.max_size
    desired_size = var.node_group_scaling.desired_size
  }

  update_config {
    max_unavailable = 1
  }

  # The original omitted the SSM attachment here, leaving a create-time race.
  depends_on = [aws_iam_role_policy_attachment.nodes]

  lifecycle {
    # The cluster autoscaler owns desired_size once the cluster is running.
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# aws_eks_node_group tags do NOT propagate to the underlying ASG, so the
# autoscaler could neither discover the groups nor pass its own IAM condition.
# These tags are what make cluster-autoscaler actually able to scale.
resource "aws_autoscaling_group_tag" "autoscaler_enabled" {
  for_each = aws_eks_node_group.private

  autoscaling_group_name = each.value.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "autoscaler_cluster" {
  for_each = aws_eks_node_group.private

  autoscaling_group_name = each.value.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}
