resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-db"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.project}-rds-"
  description = "PostgreSQL access from EKS nodes/pods"
  vpc_id      = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

# Only the EKS node security group (which pods use with the default VPC CNI) may reach 5432
resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Postgres from EKS nodes"
}

resource "aws_db_instance" "postgres" {
  identifier     = "${var.project}-pg"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class # db.t4g.micro is free-plan eligible

  # Free plan: up to 20 GB of gp2 SSD. No storage autoscaling (it could grow past the allowance).
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username

  # Fixed test password (see var.db_password). No Secrets Manager secret, no rotation.
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period    = var.db_backup_retention
  auto_minor_version_upgrade = true
  apply_immediately          = true

  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${var.project}-pg-final"
}
