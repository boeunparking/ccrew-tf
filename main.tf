terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.53.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "image_tag" {
  type        = string
  description = "ECR 이미지 태그 (CI/CD 파이프라인에서 전달)"
}

variable "certificate_arn" {
  type        = string
  description = "ALB HTTPS 리스너에 사용할 ACM 인증서 ARN"
}

module "vpc" {
  source         = "./modules/vpc"
  region         = "ap-northeast-2"
  vpc_cidr_block = "10.0.0.0/16"
  pjt_name       = "seoul-vpc"
}


### 서브넷 Subnet ###
# 서브넷 ID 참조: module.subnet["pri-sn3"].sn_id
locals {
    subnets = {
        pub-sn1 = {cidr = "10.0.0.0/24", az = "ap-northeast-2a", tier = "public"},
        pub-sn2 = {cidr = "10.0.1.0/24", az = "ap-northeast-2c", tier = "public"},
        pri-sn3 = {cidr = "10.0.2.0/24", az = "ap-northeast-2a", tier = "ecs"},
        pri-sn4 = {cidr = "10.0.3.0/24", az = "ap-northeast-2c", tier = "ecs"},
        db-sn5 = {cidr = "10.0.4.0/24", az = "ap-northeast-2a", tier = "db"},
        db-sn6 = {cidr = "10.0.5.0/24", az = "ap-northeast-2c", tier = "db"}
    }
    public_subnets = { for k, v in local.subnets : k => v if v.tier == "public" }
    ecs_subnets = { for k, v in local.subnets : k => v if v.tier == "ecs" }
    db_subnets = { for k, v in local.subnets : k => v if v.tier == "db" }

    nacl_ids = {
      alb = module.tf_alb_nacl.nacl_id
      ecs = module.tf_ecs_nacl.nacl_id
      db  = module.tf_db_nacl.nacl_id
    }

    nacl_rules = {
      # --- ALB NACL ---
      alb_ingress_https        = { nacl = "alb", rule_number = 100, egress = false, cidr_block = "0.0.0.0/0", from_port = 443,  to_port = 443 }
      alb_egress_to_user        = { nacl = "alb", rule_number = 110, egress = true,  cidr_block = "0.0.0.0/0", from_port = 1024, to_port = 65535 }
      alb_egress_to_ecr         = { nacl = "alb", rule_number = 120, egress = true,  cidr_block = "0.0.0.0/0", from_port = 443,  to_port = 443 }
      alb_ingress_from_ecr      = { nacl = "alb", rule_number = 130, egress = false, cidr_block = "0.0.0.0/0", from_port = 1024, to_port = 65535 }
      alb_egress_to_ecs_sn34     = { nacl = "alb", rule_number = 140, egress = true,  cidr_block = "10.0.2.0/23", from_port = 3000, to_port = 3000 }
      alb_ingress_from_ecs_sn34  = { nacl = "alb", rule_number = 150, egress = false, cidr_block = "10.0.2.0/23", from_port = 1024, to_port = 65535 }

      # --- ECS NACL ---
      ecs_ingress_from_alb_sn12  = { nacl = "ecs", rule_number = 200, egress = false, cidr_block = "10.0.0.0/23", from_port = 3000, to_port = 3000 }
      ecs_egress_to_alb_sn12     = { nacl = "ecs", rule_number = 210, egress = true,  cidr_block = "10.0.0.0/23", from_port = 1024, to_port = 65535 }
      ecs_egress_to_ecr         = { nacl = "ecs", rule_number = 220, egress = true,  cidr_block = "0.0.0.0/0", from_port = 443,  to_port = 443 }
      ecs_ingress_from_ecr      = { nacl = "ecs", rule_number = 230, egress = false, cidr_block = "0.0.0.0/0", from_port = 1024, to_port = 65535 }
      ecs_egress_to_db_sn56      = { nacl = "ecs", rule_number = 240, egress = true,  cidr_block = "10.0.4.0/23", from_port = 3306, to_port = 3306 }
      ecs_ingress_from_db_sn56   = { nacl = "ecs", rule_number = 250, egress = false, cidr_block = "10.0.4.0/23", from_port = 1024, to_port = 65535 }

      # --- DB NACL ---
      db_ingress_from_ecs_sn34   = { nacl = "db", rule_number = 300, egress = false, cidr_block = "10.0.2.0/23", from_port = 3306, to_port = 3306 }
      db_egress_to_ecs_sn34      = { nacl = "db", rule_number = 310, egress = true,  cidr_block = "10.0.2.0/23", from_port = 1024, to_port = 65535 }
    }

}

module "subnet" {
  source     = "./modules/subnet"
  vpc_id     = module.vpc.vpc_id
  for_each   = local.subnets
  region     = "ap-northeast-2"
  cidr_block = each.value.cidr
  az_name    = each.value.az
  pjt_name   = "tf-${each.key}"
}


### 라우팅 테이블 Routing Table ### 

# 퍼블릭 라우팅 테이블 12  
module "tf_pub_rt12" {
  source   = "./modules/route_table"
  vpc_id   = module.vpc.vpc_id
  pjt_name = "tf-pub-rt12"
}

resource "aws_route_table_association" "public" {
  for_each = local.public_subnets
  subnet_id      = module.subnet[each.key].sn_id
  route_table_id = module.tf_pub_rt12.rt_id
}

resource "aws_route" "pub_default" {
  route_table_id         = module.tf_pub_rt12.rt_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = module.vpc.igw_id
}

# EIP 
resource "aws_eip" "tf_nat_eip" {
  tags = {
    Name = "tf-nat-eip"
  }
}

# NAT 게이트웨이
resource "aws_nat_gateway" "tf_nat_gw" {
  allocation_id = aws_eip.tf_nat_eip.id
  subnet_id     = module.subnet["pub-sn1"].sn_id

  tags = {
    Name = "tf-nat-gw"
  }
  depends_on = [module.vpc.igw_id]
}

# 프라이빗 라우팅 테이블 34
module "tf_pri_rt34" {
  source   = "./modules/route_table"
  vpc_id   = module.vpc.vpc_id
  pjt_name = "tf-pri-rt34"
}

resource "aws_route_table_association" "ecs" {
  for_each = local.ecs_subnets
  subnet_id      = module.subnet[each.key].sn_id
  route_table_id = module.tf_pri_rt34.rt_id
}

resource "aws_route" "pri_default" {
  route_table_id         = module.tf_pri_rt34.rt_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_nat_gateway.tf_nat_gw.id
  depends_on             = [aws_nat_gateway.tf_nat_gw]
}

# 프라이빗 라우팅 테이블 56
module "tf_db_rt56" {
  source   = "./modules/route_table"
  vpc_id   = module.vpc.vpc_id
  pjt_name = "tf-db-rt56"
}

resource "aws_route_table_association" "db" {
  for_each = local.db_subnets
  subnet_id      = module.subnet[each.key].sn_id
  route_table_id = module.tf_db_rt56.rt_id
}


### 보안그룹 SG Security Group ### 

# ALB 보안그룹
module "alb_sg" {
  source   = "./modules/security_group"
  region   = "ap-northeast-2"
  pjt_name = "tf-alb-sg"
  vpc_id   = module.vpc.vpc_id
  desc     = "Allow HTTP, HTTPS"
}

resource "aws_vpc_security_group_ingress_rule" "tf_alb_sg_ingress_https" {
  security_group_id = module.alb_sg.sg_id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "tf_alb_sg_ingress_http" {
  security_group_id = module.alb_sg.sg_id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "tf_alb_sg_egress" {
  security_group_id = module.alb_sg.sg_id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# ECS 보안그룹
module "ecs_sg" {
  source   = "./modules/security_group"
  region   = "ap-northeast-2"
  pjt_name = "tf-ecs-sg"
  vpc_id   = module.vpc.vpc_id
  desc     = "Allow 3000"
}

resource "aws_vpc_security_group_ingress_rule" "tf_ecs_sg_ingress" {
  security_group_id            = module.ecs_sg.sg_id
  referenced_security_group_id = module.alb_sg.sg_id
  from_port                    = 3000
  ip_protocol                  = "tcp"
  to_port                      = 3000
}

resource "aws_vpc_security_group_egress_rule" "tf_ecs_sg_egress" {
  security_group_id = module.ecs_sg.sg_id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}


# DB 보안그룹
module "db_sg" {
  source   = "./modules/security_group"
  region   = "ap-northeast-2"
  pjt_name = "tf-db-sg"
  vpc_id   = module.vpc.vpc_id
  desc     = "Allow 3306"
}

resource "aws_vpc_security_group_ingress_rule" "tf_db_sg_ingress" {
  security_group_id            = module.db_sg.sg_id
  referenced_security_group_id = module.ecs_sg.sg_id
  from_port                    = 3306
  ip_protocol                  = "tcp"
  to_port                      = 3306
}


### NACL 네트워크 ACL ###

# ALB NACL
module "tf_alb_nacl"{
  source   = "./modules/nacl"
  region   = "ap-northeast-2"
  pjt_name = "tf-alb-nacl"
  vpc_id   = module.vpc.vpc_id
  subnet_ids = [module.subnet["pub-sn1"].sn_id, module.subnet["pub-sn2"].sn_id]
}

# ECS NACL
module "tf_ecs_nacl"{
  source   = "./modules/nacl"
  region   = "ap-northeast-2"
  pjt_name = "tf-ecs-nacl"
  vpc_id   = module.vpc.vpc_id
  subnet_ids = [module.subnet["pri-sn3"].sn_id, module.subnet["pri-sn4"].sn_id]
}

# DB NACL
module "tf_db_nacl"{
  source   = "./modules/nacl"
  region   = "ap-northeast-2"
  pjt_name = "tf-db-nacl"
  vpc_id   = module.vpc.vpc_id
  subnet_ids = [module.subnet["db-sn5"].sn_id, module.subnet["db-sn6"].sn_id]
}

# NACL 규칙
resource "aws_network_acl_rule" "this" {
  for_each        = local.nacl_rules
  network_acl_id  = local.nacl_ids[each.value.nacl]
  rule_number     = each.value.rule_number
  egress          = each.value.egress
  protocol        = "tcp"
  rule_action     = "allow"
  cidr_block      = each.value.cidr_block
  from_port       = each.value.from_port
  to_port         = each.value.to_port
}


# IAM Role
# ECS Task Execution Role - ECR에서 이미지 pull, CloudWatch Logs에 로그 쓰기
module "ecs_execution" {
  source = "./modules/iam_role"
  name = "ecs-execution-role"
  service = "ecs-tasks.amazonaws.com"
}
resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = module.ecs_execution.iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role - S3 접근 + Secrets Manager 접근
module "ecs_task" {
  source = "./modules/iam_role"
  name = "ecs-task-role"
  service = "ecs-tasks.amazonaws.com"
}
resource "aws_iam_role_policy_attachment" "ecs_task_s3" {
  role       = module.ecs_task.iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
resource "aws_iam_role_policy_attachment" "ecs_task_secrets" {
  role       = module.ecs_task.iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/AWSSecretsManagerClientReadOnlyAccess"
}

# Lambda Execution Role - Lambda 함수가 CloudWatch Logs에 로그 남기기 위한 기본 권한
module "lambda_execution" {
  source = "./modules/iam_role"
  name = "lambda-execution-role"
  service = "lambda.amazonaws.com"
}
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = module.lambda_execution.iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = module.lambda_execution.iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}


# ALB
module "alb" {
  source = "./modules/load_balancer"
  vpc_id = module.vpc.vpc_id
  security_group_id = module.alb_sg.sg_id
  subnet_ids = [module.subnet["pub-sn1"].sn_id, module.subnet["pub-sn2"].sn_id]
  certificate_arn = var.certificate_arn
}


# ECR
resource "aws_ecr_repository" "tf_web_ecr" {
  name = "tf-web-ecr"
}
resource "aws_ecr_repository" "tf_batch_ecr" {
  name = "tf-batch-ecr"
}


# ECS 로그 그룹
resource "aws_cloudwatch_log_group" "web" {
  name              = "/aws/ecs/web"
  retention_in_days = 1   # 1일 지난 로그는 자동 삭제
}
resource "aws_cloudwatch_log_group" "batch" {
  name              = "/aws/ecs/batch"
  retention_in_days = 1   # 1일 지난 로그는 자동 삭제
}


# ECS Cluster
resource "aws_ecs_cluster" "tf_cluster" {
  name = "tf-cluster"
}

# Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "tf_ccp" {
  cluster_name       = aws_ecs_cluster.tf_cluster.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# Task Definition - Web (Fargate)
module "web_service" {
  source = "./modules/ecs_service"

  name               = "clduck-web"
  cluster_id = aws_ecs_cluster.tf_cluster.id
  cluster_name = aws_ecs_cluster.tf_cluster.name
  ecr_repository_url = aws_ecr_repository.tf_web_ecr.repository_url
  image_tag          = var.image_tag
  execution_role_arn = module.ecs_execution.iam_role_arn
  task_role_arn      = module.ecs_task.iam_role_arn
  log_group          = aws_cloudwatch_log_group.web.name

  container_port = 3000
  environment = [
    { name = "ENV", value = "production" }
  ]

  desired_count = 2
  launch_type   = "FARGATE"
  capacity_providers_dependency = aws_ecs_cluster_capacity_providers.tf_ccp

  target_group_arn = module.alb.alb_tg_arn

  subnets = [module.subnet["pri-sn3"].sn_id, module.subnet["pri-sn4"].sn_id]
  security_groups = [module.ecs_sg.sg_id]

  enable_autoscaling       = true
  autoscaling_min_capacity = 2
  autoscaling_max_capacity = 10
  autoscaling_cpu_target   = 60
}

module "batch_service" {
  source = "./modules/ecs_service"

  name               = "clduck-batch"
  cluster_id = aws_ecs_cluster.tf_cluster.id
  cluster_name = aws_ecs_cluster.tf_cluster.name
  ecr_repository_url = aws_ecr_repository.tf_batch_ecr.repository_url
  image_tag          = var.image_tag
  execution_role_arn = module.ecs_execution.iam_role_arn
  task_role_arn      = module.ecs_task.iam_role_arn
  log_group          = aws_cloudwatch_log_group.batch.name

  environment = [
    { name = "QUEUE_NAME", value = "batch-jobs" }
  ]

  desired_count     = 3
  capacity_provider = "FARGATE_SPOT" # launch_type 안 주면 이걸로 100% Spot 실행

  subnets = [module.subnet["pri-sn3"].sn_id, module.subnet["pri-sn4"].sn_id]
  security_groups = [module.ecs_sg.sg_id]

  enable_autoscaling       = true
  autoscaling_min_capacity = 2
  autoscaling_max_capacity = 6
  autoscaling_cpu_target   = 60
}


# 로그 정리 Lambda
module "log_cleanup_execution" {
  source  = "./modules/iam_role"
  name    = "log-cleanup-lambda-role"
  service = "lambda.amazonaws.com"
}
# Lambda 함수 자기 자신의 실행 로그를 CloudWatch에 쓰는 권한
resource "aws_iam_role_policy_attachment" "log_cleanup_basic_execution" {
  role       = module.log_cleanup_execution.iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# 다른 로그 그룹들(예: /aws/ecs/web, /aws/ecs/batch)을 조회하고 삭제하는 권한
resource "aws_iam_role_policy_attachment" "log_cleanup_permissions" {
  role       = module.log_cleanup_execution.iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

# 특정 이벤트가 발생했을 때 실행될 코드(로직) 정의
module "log_cleanup" {
  source     = "./modules/lambda_function"
  name       = "clduck-log-cleanup"
  source_dir = "${path.module}/modules/lambda/log_cleanup"
  role_arn   = module.log_cleanup_execution.iam_role_arn
  timeout    = 60

  environment = {
    RETENTION_DAYS   = "1"
    LOG_GROUP_PREFIX = "/aws/ecs/"
  }
}

# 시간 기반 이벤트(스케줄)를 정의
resource "aws_cloudwatch_event_rule" "log_cleanup_schedule" {
  name                = "clduck-log-cleanup-schedule"
  description         = "매일 새벽 2시(KST)에 오래된 로그 스트림 정리"
  # 매일 새벽 2시(KST, UTC+9) = 전날 17:00 UTC
  schedule_expression = "cron(0 17 * * ? *)"
}

# 위에서 정의한 이벤트가 발생했을 때 실행시킬 타겟 람다 함수를 정의 (여기서는 모듈 log_cleanup)
resource "aws_cloudwatch_event_target" "log_cleanup_target" {
  rule = aws_cloudwatch_event_rule.log_cleanup_schedule.name
  arn  = module.log_cleanup.function_arn
}

# EventBridge가 Lambda를 호출해도 되는지, Lambda 쪽에서 허락해주는 코드
resource "aws_lambda_permission" "allow_eventbridge_log_cleanup" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = module.log_cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.log_cleanup_schedule.arn
}