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
  pjt_name       = "vpc-seoul"
}

module "tf_pub_sn1" {
  source        = "./modules/subnet"
  region        = "ap-northeast-2"
  vpc_id        = module.vpc.vpc_id
  sn_cidr_block = "10.0.1.0/24"
  az_name       = "ap-northeast-2a"
}

module "tf_pri_sn2" {
  source        = "./modules/subnet"
  region        = "ap-northeast-2"
  vpc_id        = module.vpc.vpc_id
  sn_cidr_block = "10.0.2.0/24"
  az_name       = "ap-northeast-2a"
}

module "tf_pri_sn3" {
  source        = "./modules/subnet"
  region        = "ap-northeast-2"
  vpc_id        = module.vpc.vpc_id
  sn_cidr_block = "10.0.3.0/24"
  az_name       = "ap-northeast-2c"
}

module "tf_db_sn4" {
  source        = "./modules/subnet"
  region        = "ap-northeast-2"
  vpc_id        = module.vpc.vpc_id
  sn_cidr_block = "10.0.4.0/24"
  az_name       = "ap-northeast-2a"
}

module "tf_db_sn5" {
  source        = "./modules/subnet"
  region        = "ap-northeast-2"
  vpc_id        = module.vpc.vpc_id
  sn_cidr_block = "10.0.5.0/24"
  az_name       = "ap-northeast-2c"
}


# 퍼블릭 라우팅 테이블 12  
module "tf_pub_rt1" {
    source = "./modules/route_table"
    vpc_id = module.vpc.vpc_id
    pjt_name = "ccrew-pub-rt1"
}

resource "aws_route_table_association" "tf_rt_sn_ass1" {
  subnet_id       = module.tf_pub_sn1.sn_id
  route_table_id  = module.tf_pub_rt1.rt_id
}

resource "aws_route" "pub_default" {
    route_table_id = module.tf_pub_rt1.rt_id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = module.vpc.igw_id
}

# EIP 
resource "aws_eip" "tf_nat_eip" {
  tags = {
    Name = "${var.region}-nat-eip"
  }
}

# NAT 게이트웨이
resource "aws_nat_gateway" "tf_nat_gw" {
  allocation_id = aws_eip.tf_nat_eip.id
  subnet_id     = module.tf_pub_sn1.sn_id

  tags = {
    Name = "${var.region}-nat-gw"
  }
  depends_on = [module.vpc.igw_id]
}

# 프라이빗 라우팅 테이블 23
module "tf_pri_rt23" {
    source = "./modules/route_table"
    vpc_id = module.vpc.vpc_id
    pjt_name = "ccrew-pri-rt23"
}

resource "aws_route_table_association" "tf_rt_sn_ass2" {
  subnet_id       = module.tf_pri_sn2.sn_id
  route_table_id  = module.tf_pri_rt23.rt_id
}
resource "aws_route_table_association" "tf_rt_sn_ass3" {
  subnet_id       = module.tf_pri_sn3.sn_id
  route_table_id  = module.tf_pri_rt23.rt_id
}

resource "aws_route" "pri_default" {
    route_table_id = module.tf_pri_rt23.rt_id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.tf_nat_gw.id
    depends_on = [aws_nat_gateway.tf_nat_gw]
}

# 프라이빗 라우팅 테이블 45
module "tf_db_rt45" {
    source = "./modules/route_table"
    vpc_id = module.vpc.vpc_id
    pjt_name = "ccrew-db-rt45"
}

resource "aws_route_table_association" "tf_rt_sn_ass4" {
  subnet_id       = module.tf_db_sn4.sn_id
  route_table_id  = module.tf_db_rt45.rt_id
}
resource "aws_route_table_association" "tf_rt_sn_ass5" {
  subnet_id       = module.tf_db_sn5.sn_id
  route_table_id  = module.tf_db_rt45.rt_id
}

# ALB 보안그룹
module "alb_sg" {
  source   = "./modules/security_group"
  region   = "ap-northeast-2"
  pjt_name = "ccrew-alb"
  vpc_id   = module.vpc.vpc_id
  desc = "Allow HTTP, HTTPS"
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
  pjt_name = "ccrew-ecs"
  vpc_id   = module.vpc.vpc_id
  desc = "Allow 3000"
}

resource "aws_vpc_security_group_ingress_rule" "tf_ecs_sg_ingress" {
  security_group_id = module.ecs_sg.sg_id
  referenced_security_group_id = module.alb_sg.sg_id
  from_port         = 3000
  ip_protocol       = "tcp"
  to_port           = 3000
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
  pjt_name = "ccrew-db"
  vpc_id   = module.vpc.vpc_id
  desc = "Allow 3306"
}

resource "aws_vpc_security_group_ingress_rule" "tf_db_sg_ingress" {
  security_group_id = module.db_sg.sg_id
  referenced_security_group_id = module.ecs_sg.sg_id
  from_port         = 3306
  ip_protocol       = "tcp"
  to_port           = 3306
}

