resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${var.cluster_name}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust["cluster-autoscaler"].json
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name = "${var.cluster_name}-cluster-autoscaler"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeTags",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeImages",
          "eks:DescribeNodegroup",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            # Satisfied by aws_autoscaling_group_tag.autoscaler_cluster in
            # eks-nodes.tf. Without that tag this condition never matched and
            # the autoscaler was silently denied every scaling call.
            "aws:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}
