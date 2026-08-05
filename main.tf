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

module "tf_pub_sn1" {
  source        = "./modules/subnet"
  region        = "ap-northeast-2"
  vpc_id        = module.vpc.vpc_id
  cidr_block = "10.0.1.0/24"
  az_name       = "ap-northeast-2a"
  pjt_name      = "tf-pub-sn1"
}

module "tf_pri_sn2" {
  source        = "./modules/subnet"
  region        = "ap-northeast-2"
  vpc_id        = module.vpc.vpc_id
  cidr_block = "10.0.2.0/24"
  az_name       = "ap-northeast-2a"
  pjt_name      = "tf-pri-sn2"
}

module "tf_pri_sn3" {
  source        = "./modules/subnet"
  region        = "ap-northeast-2"
  vpc_id        = module.vpc.vpc_id
  cidr_block = "10.0.3.0/24"
  az_name       = "ap-northeast-2c"
  pjt_name      = "tf-pri-sn3"
}

module "tf_db_sn4" {
  source        = "./modules/subnet"
  region        = "ap-northeast-2"
  vpc_id        = module.vpc.vpc_id
  cidr_block =    "10.0.4.0/24"
  az_name       = "ap-northeast-2a"
  pjt_name      = "tf-db-sn4"
}

module "tf_db_sn5" {
  source        = "./modules/subnet"
  region        = "ap-northeast-2"
  vpc_id        = module.vpc.vpc_id
  cidr_block = "10.0.5.0/24"
  az_name       = "ap-northeast-2c"
  pjt_name      = "tf-db-sn5"
}


# 퍼블릭 라우팅 테이블 12  
module "tf_pub_rt1" {
  source   = "./modules/route_table"
  vpc_id   = module.vpc.vpc_id
  pjt_name = "tf-pub-rt1"
}

resource "aws_route_table_association" "tf_rt_sn_ass1" {
  subnet_id      = module.tf_pub_sn1.sn_id
  route_table_id = module.tf_pub_rt1.rt_id
}

resource "aws_route" "pub_default" {
  route_table_id         = module.tf_pub_rt1.rt_id
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
  subnet_id     = module.tf_pub_sn1.sn_id

  tags = {
    Name = "tf-nat-gw"
  }
  depends_on = [module.vpc.igw_id]
}

# 프라이빗 라우팅 테이블 23
module "tf_pri_rt23" {
  source   = "./modules/route_table"
  vpc_id   = module.vpc.vpc_id
  pjt_name = "tf-pri-rt23"
}

resource "aws_route_table_association" "tf_rt_sn_ass2" {
  subnet_id      = module.tf_pri_sn2.sn_id
  route_table_id = module.tf_pri_rt23.rt_id
}
resource "aws_route_table_association" "tf_rt_sn_ass3" {
  subnet_id      = module.tf_pri_sn3.sn_id
  route_table_id = module.tf_pri_rt23.rt_id
}

resource "aws_route" "pri_default" {
  route_table_id         = module.tf_pri_rt23.rt_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_nat_gateway.tf_nat_gw.id
  depends_on             = [aws_nat_gateway.tf_nat_gw]
}

# 프라이빗 라우팅 테이블 45
module "tf_db_rt45" {
  source   = "./modules/route_table"
  vpc_id   = module.vpc.vpc_id
  pjt_name = "tf-db-rt45"
}

resource "aws_route_table_association" "tf_rt_sn_ass4" {
  subnet_id      = module.tf_db_sn4.sn_id
  route_table_id = module.tf_db_rt45.rt_id
}
resource "aws_route_table_association" "tf_rt_sn_ass5" {
  subnet_id      = module.tf_db_sn5.sn_id
  route_table_id = module.tf_db_rt45.rt_id
}

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

# ALB NACL
module "tf_alb_nacl"{
  source   = "./modules/nacl"
  region   = "ap-northeast-2"
  pjt_name = "tf-alb-nacl"
  vpc_id   = module.vpc.vpc_id
  subnet_ids = [module.tf_pub_sn1.sn_id]
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

# ECS NACL
module "tf_ecs_nacl"{
  source   = "./modules/nacl"
  region   = "ap-northeast-2"
  pjt_name = "tf-ecs-nacl"
  vpc_id   = module.vpc.vpc_id
  subnet_ids = [module.tf_pri_sn2.sn_id, module.tf_pri_sn3.sn_id]
}

# ECS NACL RULE ingress 3000
resource "aws_network_acl_rule" "tf_ecs_nacl_ingress_to_alb" {
  network_acl_id = module.tf_ecs_nacl.nacl_id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = module.tf_pub_sn1.cidr_block
  from_port      = 3000
  to_port        = 3000
}

# ECS NACL Rule Egress 1024-65535
resource "aws_network_acl_rule" "tf_ecs_nacl_egress_to_alb" {
  network_acl_id = module.tf_ecs_nacl.nacl_id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# DB NACL
module "tf_db_nacl"{
  source   = "./modules/nacl"
  region   = "ap-northeast-2"
  pjt_name = "tf-db-nacl"
  vpc_id   = module.vpc.vpc_id
  subnet_ids = [module.tf_db_sn4.sn_id, module.tf_db_sn5.sn_id]
}

# DB NACL Rule ingress 3306
resource "aws_network_acl_rule" "tf_db_nacl_ingress_to_ecs" {
  network_acl_id = module.tf_db_nacl.nacl_id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.db_tier_cidr
  from_port      = 3306
  to_port        = 3306
}

# DB NACL Rule Egress 1024-65535
resource "aws_network_acl_rule" "tf_db_nacl_egress_to_ecs" {
  network_acl_id = module.tf_db_nacl.nacl_id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}