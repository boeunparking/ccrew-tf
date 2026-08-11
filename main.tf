terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.53.0"
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
        pub-sn1 = {cidr = "10.0.1.0/24", az = "ap-northeast-2a", tier = "public"},
        pub-sn2 = {cidr = "10.0.2.0/24", az = "ap-northeast-2c", tier = "public"},
        pri-sn3 = {cidr = "10.0.3.0/24", az = "ap-northeast-2a", tier = "ecs"},
        pri-sn4 = {cidr = "10.0.4.0/24", az = "ap-northeast-2c", tier = "ecs"},
        db-sn5 = {cidr = "10.0.5.0/24", az = "ap-northeast-2a", tier = "db"},
        db-sn6 = {cidr = "10.0.6.0/24", az = "ap-northeast-2c", tier = "db"}
    }
    public_subnets = { for k, v in local.subnets : k => v if v.tier == "public" }
    ecs_subnets = { for k, v in local.subnets : k => v if v.tier == "ecs" }
    db_subnets = { for k, v in local.subnets : k => v if v.tier == "db" }
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

###  ALB NACL  ###
module "tf_alb_nacl"{
  source   = "./modules/nacl"
  region   = "ap-northeast-2"
  pjt_name = "tf-alb-nacl"
  vpc_id   = module.vpc.vpc_id
  subnet_ids = [module.subnet["pub-sn1"].sn_id, module.subnet["pub-sn2"].sn_id]
}

# ALB NACL Ingress Rule 443
resource "aws_network_acl_rule" "tf_alb_nacl_rule" {
  network_acl_id = module.tf_alb_nacl.nacl_id
  rule_number    = 100
  # egress: egress 인수는 이 규칙이 egress인지 나타냄. 기본값은 false
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  # cidr_block: 허용 또는 거부할 네트워크 범위를 CIDR 표기법으로 지정
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

# ALB NACL Egress Rule 1024 ~ 65535
# 왜 포트 범위 1024 ~ 65535냐면 목적지 포트는 랜덤이니 에페메럴 범위 전체로 씀
# 에페메럴 포트: 일시적인/임시 포트
resource "aws_network_acl_rule" "tf_alb_nacl_out_ephemeral" {
  network_acl_id = module.tf_alb_nacl.nacl_id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# NAT -> ECR 요청
resource "aws_network_acl_rule" "tf_alb_nat_ecr_egress" {
  network_acl_id = module.tf_alb_nacl.nacl_id
  rule_number    = 120
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

# ECR -> NAT 응답
resource "aws_network_acl_rule" "tf_alb_nat_ecr_ingress" {
  network_acl_id = module.tf_alb_nacl.nacl_id
  rule_number    = 130
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# ALB -> ECS 요청
resource "aws_network_acl_rule" "tf_alb_ecs_egress1" {
  network_acl_id = module.tf_alb_nacl.nacl_id
  rule_number    = 140
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["pri-sn3"].cidr_block   
  from_port      = 3000
  to_port        = 3000
}

resource "aws_network_acl_rule" "tf_alb_ecs_egress2" {
  network_acl_id = module.tf_alb_nacl.nacl_id
  rule_number    = 141
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["pri-sn4"].cidr_block   
  from_port      = 3000
  to_port        = 3000
}

# ECS -> ALB 응답
resource "aws_network_acl_rule" "tf_alb_ecs_ingress1" {
  network_acl_id = module.tf_alb_nacl.nacl_id
  rule_number    = 150
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["pri-sn3"].cidr_block   
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "tf_alb_ecs_ingress2" {
  network_acl_id = module.tf_alb_nacl.nacl_id
  rule_number    = 151
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["pri-sn4"].cidr_block   
  from_port      = 1024
  to_port        = 65535
}


###   ECS NACL  ###

module "tf_ecs_nacl"{
  source   = "./modules/nacl"
  region   = "ap-northeast-2"
  pjt_name = "tf-ecs-nacl"
  vpc_id   = module.vpc.vpc_id
  subnet_ids = [module.subnet["pri-sn3"].sn_id, module.subnet["pri-sn4"].sn_id]
}

# ECS NACL RULE ingress 3000
resource "aws_network_acl_rule" "tf_ecs_nacl_ingress1" {
  network_acl_id = module.tf_ecs_nacl.nacl_id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["pub-sn1"].cidr_block
  from_port      = 3000
  to_port        = 3000
}

resource "aws_network_acl_rule" "tf_ecs_nacl_ingress2" {
  network_acl_id = module.tf_ecs_nacl.nacl_id
  rule_number    = 201
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["pub-sn2"].cidr_block
  from_port      = 3000
  to_port        = 3000
}

# ECS NACL Rule Egress 1024-65535
resource "aws_network_acl_rule" "tf_ecs_nacl_egress1" {
  network_acl_id = module.tf_ecs_nacl.nacl_id
  rule_number    = 210
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["pub-sn1"].cidr_block
  from_port      = 1024
  to_port        = 65535
}

# ECS NACL Rule Egress 1024-65535
resource "aws_network_acl_rule" "tf_ecs_nacl_egress2" {
  network_acl_id = module.tf_ecs_nacl.nacl_id
  rule_number    = 211
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["pub-sn2"].cidr_block
  from_port      = 1024
  to_port        = 65535
}

# ECS -> ECR 요청
resource "aws_network_acl_rule" "tf_ecs_ecr_egress" {
  network_acl_id = module.tf_ecs_nacl.nacl_id
  rule_number    = 220
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

# ECR -> ECS 응답
resource "aws_network_acl_rule" "tf_ecs_ecr_ingress" {
  network_acl_id = module.tf_ecs_nacl.nacl_id
  rule_number    = 230
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}


# ECS -> DB 요청1
resource "aws_network_acl_rule" "tf_ecs_db_egress1" {
  network_acl_id = module.tf_ecs_nacl.nacl_id
  rule_number    = 240
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["db-sn5"].cidr_block
  from_port      = 3306
  to_port        = 3306
}

# ECS -> DB 요청2
resource "aws_network_acl_rule" "tf_ecs_db_egress2" {
  network_acl_id = module.tf_ecs_nacl.nacl_id
  rule_number    = 241
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["db-sn6"].cidr_block
  from_port      = 3306
  to_port        = 3306
}

# DB -> ECS 응답
resource "aws_network_acl_rule" "tf_ecs_db_ingress1" {
  network_acl_id = module.tf_ecs_nacl.nacl_id
  rule_number    = 250
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["db-sn5"].cidr_block
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "tf_ecs_db_ingress2" {
  network_acl_id = module.tf_ecs_nacl.nacl_id
  rule_number    = 251
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["db-sn6"].cidr_block
  from_port      = 1024
  to_port        = 65535
}


# DB NACL
module "tf_db_nacl"{
  source   = "./modules/nacl"
  region   = "ap-northeast-2"
  pjt_name = "tf-db-nacl"
  vpc_id   = module.vpc.vpc_id
  subnet_ids = [module.subnet["db-sn5"].sn_id, module.subnet["db-sn6"].sn_id]
}

# ECS -> DB 요청
resource "aws_network_acl_rule" "tf_db_ecs_ingress1" {
  network_acl_id = module.tf_db_nacl.nacl_id
  rule_number    = 300
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["pri-sn3"].cidr_block
  from_port      = 3306
  to_port        = 3306
}

resource "aws_network_acl_rule" "tf_db_ecs_ingress2" {
  network_acl_id = module.tf_db_nacl.nacl_id
  rule_number    = 301
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["pri-sn4"].cidr_block
  from_port      = 3306
  to_port        = 3306
}

# DB -> ECS 응답
resource "aws_network_acl_rule" "tf_db_ecs_egress1" {
  network_acl_id = module.tf_db_nacl.nacl_id
  rule_number    = 310
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["pri-sn3"].cidr_block
  from_port      = 1024
  to_port        = 65535
}

# DB NACL Rule Egress 1024-65535
resource "aws_network_acl_rule" "tf_db_ecs_egress2" {
  network_acl_id = module.tf_db_nacl.nacl_id
  rule_number    = 311
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.subnet["pri-sn4"].cidr_block
  from_port      = 1024
  to_port        = 65535
}