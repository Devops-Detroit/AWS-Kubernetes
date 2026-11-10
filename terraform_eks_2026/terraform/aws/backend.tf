# Remote state with native S3 locking (use_lockfile), which replaced the
# DynamoDB lock table. The original config had no backend at all and the
# pipeline committed terraform.tfstate into this public repo — state holds
# resource attributes in plaintext and must never be versioned in git.
#
# Configured at init time so the same code works locally and in CI:
#
#   terraform init -backend-config=backend.hcl
#
# Create the bucket once before the first init:
#
#   aws s3api create-bucket --bucket <name> --region <region> \
#     --create-bucket-configuration LocationConstraint=<region>
#   aws s3api put-bucket-versioning --bucket <name> \
#     --versioning-configuration Status=Enabled
#
# To run without remote state (throwaway/local only):
#
#   terraform init -backend=false

terraform {
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
