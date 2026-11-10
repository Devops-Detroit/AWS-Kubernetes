# Kubernetes Cluster with AWS EKS and Terraform

Provisions a VPC, an EKS cluster, managed node groups, and the in-cluster
controllers needed for ALB Ingress and node autoscaling. GitHub Actions drives
plan/apply/destroy on manual dispatch.

## Layout

```
terraform/aws/
  versions.tf                     Terraform + provider version constraints
  providers.tf                    AWS and Helm provider config
  backend.tf                      S3 remote state (partial config)
  variables.tf                    All tunables
  vpc.tf                          VPC, subnets, IGW, NAT, route tables
  eks-cluster.tf                  Control plane, IAM, log group, access config
  eks-nodes.tf                    Node IAM, managed node groups, ASG tags
  iam-oidc.tf                     OIDC provider and shared IRSA trust policies
  addons.tf                       vpc-cni, coredns, kube-proxy, EBS CSI driver
  aws-load-balancer-controller.tf IRSA role and policy
  cluster-autoscaler.tf           IRSA role and policy
  helm-releases.tf                Installs both controllers
  outputs.tf
kubernetes/manifests/             Sample workloads and Ingresses
.github/workflows/aws-infra.yaml  CI pipeline
```

## Prerequisites

- AWS account and configured AWS CLI v2
- Terraform >= 1.9
- kubectl
- An S3 bucket for remote state

Create the state bucket once:

```bash
aws s3api create-bucket --bucket <name> --region <region> \
  --create-bucket-configuration LocationConstraint=<region>
aws s3api put-bucket-versioning --bucket <name> \
  --versioning-configuration Status=Enabled
```

## Deploy

```bash
cd terraform/aws
cp backend.hcl.example backend.hcl   # fill in your bucket
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Then point kubectl at the cluster:

```bash
aws eks update-kubeconfig --region eu-north-1 --name eks-cluster
kubectl apply -f ../../kubernetes/manifests/
```

### If the first apply fails on the Helm provider

Terraform configures the Helm provider from the cluster this same run creates.
Usually fine, but if you hit `Kubernetes cluster unreachable` on a cold apply,
build the infrastructure first and add the controllers second:

```bash
terraform apply -var="install_helm_releases=false"
terraform apply
```

## Configuration

Everything is in `variables.tf`. The ones you are most likely to change:

| Variable | Default | Notes |
|---|---|---|
| `region` | `eu-north-1` | Must match `availability_zones` |
| `cluster_version` | `1.33` | Verify with `aws eks describe-cluster-versions` |
| `node_instance_types` | `["t3.medium"]` | `t3.small` caps at 11 pods/node |
| `node_group_scaling` | min 1 / max 3 / desired 1 | Per AZ |
| `single_nat_gateway` | `true` | `false` gives one NAT per AZ (resilient, ~3x cost) |
| `cluster_endpoint_public_access_cidrs` | `["0.0.0.0/0"]` | Narrow this for anything real |
| `install_helm_releases` | `true` | See two-phase apply above |

## CI/CD

`.github/workflows/aws-infra.yaml` runs on manual dispatch with inputs for
environment, region, action (`plan` / `apply` / `destroy`), and whether to apply
the manifests afterward.

Repository **variables**: `TF_STATE_BUCKET`, `TF_STATE_REGION`, `CLUSTER_NAME`,
and `AWS_ROLE_ARN` if using OIDC.
Repository **secrets** (only if not using OIDC): `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`.

Prefer OIDC — set `AWS_ROLE_ARN` and delete the two access-key secrets. The
workflow already requests `id-token: write`.

## Not included

The `monitoring` namespace and `grafana-ingress.yaml` expect kube-prometheus-stack,
which this repo does not install. Add it before applying that Ingress:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring
```

The sample Ingresses use `*.ddns.net` hostnames that you will need to repoint at
your own ALB.

## Teardown

```bash
kubectl delete -f kubernetes/manifests/   # release ALBs first
cd terraform/aws && terraform destroy
```

Deleting Ingresses before `terraform destroy` matters — orphaned ALBs and their
security groups will block the VPC from being deleted.
