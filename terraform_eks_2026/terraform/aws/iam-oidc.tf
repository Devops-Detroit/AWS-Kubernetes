data "tls_certificate" "eks_cluster" {
  url = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks_cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

locals {
  oidc_issuer_host = replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")

  # service account name => the IAM role it federates into
  irsa_service_accounts = toset([
    "aws-load-balancer-controller",
    "cluster-autoscaler",
    "ebs-csi-controller-sa",
  ])
}

# One IRSA trust policy per kube-system service account. The original repeated
# this three times and omitted the :aud condition, which left the roles
# assumable by any audience presenting a matching subject.
data "aws_iam_policy_document" "irsa_trust" {
  for_each = local.irsa_service_accounts

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks_cluster.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:kube-system:${each.value}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}
