variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "aws_profile" {
  description = "Named AWS CLI profile (e.g. an SSO profile). Leave null to use env vars."
  type        = string
  default     = null
}

variable "project" {
  description = "Prefix for resource names"
  type        = string
  default     = "journal-starter"
}

# ---------- ECR ----------
variable "ecr_repo_name" {
  type    = string
  default = "journalrepo"
}

variable "ecr_force_delete" {
  description = "Allow terraform destroy to delete the repo even if it holds images"
  type        = bool
  default     = true
}

# ---------- EKS ----------
variable "cluster_version" {
  description = "Kubernetes version. Check which versions EKS currently supports in eu-west-2."
  type        = string
  default     = "1.34"
}

# Free-plan-eligible EC2 types (accounts created on/after 2025-07-15), per AWS docs.
# t3.micro is too small for EKS (only ~4 pods fit per node), so default to t3.small.
# t4g.* are ARM (Graviton); the ami_type in eks.tf switches automatically.
variable "node_instance_type" {
  type    = string
  default = "t3.small"

  validation {
    condition = contains(
      ["t3.micro", "t3.small", "t4g.micro", "t4g.small", "c7i-flex.large", "m7i-flex.large"],
      var.node_instance_type
    )
    error_message = "Not a free-plan-eligible instance type. Run: aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true --region eu-west-2 --query 'InstanceTypes[].InstanceType'"
  }
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_desired_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 2
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. Restrict this to your own IP (x.x.x.x/32)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------- RDS ----------
variable "db_name" {
  type    = string
  default = "career_journal"
}

variable "db_username" {
  type    = string
  default = "postgres"
}

# TEST SETUP ONLY: a fixed, well-known password, same as the CI database.
# The instance is private (reachable only from the EKS nodes), but replace this
# and switch back to manage_master_user_password before holding real data.
variable "db_password" {
  type      = string
  default   = "postgres" # RDS requires at least 8 characters
  sensitive = true
}

variable "db_engine_version" {
  type    = string
  default = "16"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

# Free plan caps automated backup retention (7 failed with FreeTierRestrictionError).
# If 1 is still rejected, set to 0 (automated backups off).
variable "db_backup_retention" {
  type    = number
  default = 1
}

variable "db_multi_az" {
  type    = bool
  default = false
}

# Dev-friendly defaults. For production: deletion_protection = true, skip_final_snapshot = false.
variable "db_deletion_protection" {
  type    = bool
  default = false
}

variable "db_skip_final_snapshot" {
  type    = bool
  default = true
}

# ---------- App identity (for reading the DB secret from pods) ----------
variable "app_namespace" {
  type    = string
  default = "default"
}

variable "app_service_account" {
  type    = string
  default = "app"
}
