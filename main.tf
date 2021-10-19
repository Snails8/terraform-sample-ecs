# CI/CD で使用 (無駄な使用を避けるためあえてコメントアウトしている)
#terraform {
#  backend "s3" {
#    bucket = "バケット名を指定"
#    key    = "terraform.tfstate"
#    region = "ap-northeast-1"
#
#  }
#  required_providers {
#    aws = {
#      source  = "hashicorp/aws"
#      version = "~> 3.27"
#    }
#  }
#  required_version = ">= 0.14.9"
#}

# provider の設定 ( provider は aws 専用ではなくGCPとかも使える)
provider "aws" {
  region = "ap-northeast-1"
}

variable "app_name" {
  type = string
  default = "sample"
}

# AZ の設定(冗長化のため配列でlist化してある)
variable "azs" {
  type = list(string)
  default = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
}

# ELB で使用 https化に使う
variable "domain" {
  type = string
  default = "sample.com"
}

# acm で使用 (TLS証明書)
variable "zone" {
  type = string
  default = "sample.com"
}

variable "LOKI_USER" {
  type = string
}

variable "LOKI_PASS" {
  type = string
}

# ========================================================
# Network 作成
#
# VPC, subnet(pub, pri), IGW, RouteTable, Route, RouteTableAssociation
# ========================================================
module "network" {
  source = "./network"
  app_name = var.app_name
  azs = var.azs
}

# ========================================================
# EC2 (vpc_id, subnet_id が必要)
#
# ========================================================
module "ec2" {
  source = "./ec2"
  app_name = var.app_name
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.ec2_subnet_id
}

# ========================================================
# ECS 作成
#
# ECS(service, cluster elb
# ========================================================
module "ecs" {
  source = "./ecs/app"
  app_name = var.app_name
  vpc_id   = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids

  cluster_name = module.ecs_cluster.cluster_name
  # elb の設定
  https_listener_arn  = module.elb.https_listener_arn
  # ECS のtask に関連付けるIAM の設定
  iam_role_task_execution_arn = module.iam.iam_role_task_execution_arn

  loki_user = var.LOKI_USER
  loki_pass = var.LOKI_PASS
}

# cluster 作成
module "ecs_cluster" {
  source   = "./ecs/cluster"
  app_name = var.app_name
}

# ACM 発行
module "acm" {
  source   = "./acm"
  app_name = var.app_name
  zone     = var.zone
  domain   = var.domain
}

# ELB の設定
module "elb" {
  source            = "./elb"
  app_name          = var.app_name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids

  domain = var.domain
  zone   = var.zone
  acm_id = module.acm.acm_id
}

# IAM 設定
# ECS-Agentが使用するIAMロール や タスク(=コンテナ)に付与するIAMロール の定義
module "iam" {
  source = "./iam"
  app_name = var.app_name
}


# ========================================================
# RDS 作成
#
# [subnetGroup, securityGroup, RDS instance(postgreSQL)]
# ========================================================

variable "DB_NAME" {
  type = string
}

variable "DB_MASTER_NAME" {
  type = string
}

variable "DB_MASTER_PASS" {
  type = string
}

# RDS (PostgreSQL)
module "rds" {
  source = "./rds"

  app_name = var.app_name
  vpc_id   = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  database_name   = var.DB_NAME
  master_username = var.DB_MASTER_NAME
  master_password = var.DB_MASTER_PASS
}