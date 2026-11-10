variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-north-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "eks-cluster"
}

# Verify this is still a supported version before applying:
#   aws eks describe-cluster-versions --query 'clusterVersions[].clusterVersion'
# Pinning matters — an unpinned cluster silently drifts to whatever EKS
# defaults to, which is what broke the original config's addon pin.
variable "cluster_version" {
  description = "Kubernetes minor version for the EKS control plane."
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread subnets and node groups across. Must be in var.region."
  type        = list(string)
  default     = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all private subnets (cheaper) instead of one per AZ (resilient)."
  type        = bool
  default     = true
}

variable "node_instance_types" {
  description = "Instance types for the managed node groups."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_scaling" {
  description = "Per-AZ node group sizing. max must exceed min for the cluster autoscaler to do anything."
  type = object({
    min_size     = number
    max_size     = number
    desired_size = number
  })
  default = {
    min_size     = 1
    max_size     = 3
    desired_size = 1
  }
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Narrow this from 0.0.0.0/0 for anything real."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Leave null to take the latest chart. Pin both for reproducible deploys.
variable "alb_controller_chart_version" {
  description = "Chart version for aws-load-balancer-controller, or null for latest."
  type        = string
  default     = null
}

variable "cluster_autoscaler_chart_version" {
  description = "Chart version for cluster-autoscaler, or null for latest."
  type        = string
  default     = null
}

variable "install_helm_releases" {
  description = "Install the in-cluster controllers. Set false for the first apply if Terraform cannot reach the API server yet (see README)."
  type        = bool
  default     = true
}
