############################################################
# cloud-duck 인프라
# 서울(Active) + 도쿄(Warm Standby/DR)
#
# 모듈 6종
#   1. rds          : Primary(Multi-AZ) + Replica + 도쿄 크로스리전 Replica
#   2. elasticache  : Valkey (cache.t4g.micro, 단일 노드) — 양 리전
#   3. s3           : Source(서울) + CRR(도쿄)
#   4. client-vpn   : 관리자 → DB 접근 (서울)
#   5. cloudwatch   : CPU 80% 5분 알람 + SNS + 대시보드
#   6. vpc-peering  : Site-to-Site VPN 대체 (구성도 표기만 VPN)
#
# 네트워크(VPC/Subnet/RouteTable/SG/NACL)는 ccrew-tf 의 region_stack 모듈이
# 서울(172.16.0.0/16) / 도쿄(172.17.0.0/16) 두 리전에 이미 생성한다.
# ccrew-tf 와는 state 가 분리되어 있으므로 여기서는 ID 를 변수로 받는다.
############################################################

########################################
# 1. RDS — 서울: Primary(Multi-AZ) + 같은 리전 Replica
########################################
module "rds_seoul" {
  source = "./modules/rds"
  providers = {
    aws = aws.seoul
  }

  project    = var.project
  name       = "seoul"
  vpc_id     = var.seoul_vpc_id
  subnet_ids = var.seoul_db_subnet_ids # tf-seoul-db-sn5, tf-seoul-db-sn6
  ecs_sg_id  = var.seoul_ecs_sg_id     # tf-seoul-ecs-sg

  # VPN 관리자 → DB 3306 허용 (VPN 관리자 접근 매트릭스)
  vpn_client_cidr = var.vpn_client_cidr

  create_primary = true
  multi_az       = true # RDS(multi-az) 결정사항
  create_replica = true # RDS replica (db.t4g.micro)
}

########################################
# 1'. RDS — 도쿄: 크로스 리전 Read Replica (Warm Standby)
########################################
module "rds_tokyo_replica" {
  source = "./modules/rds"
  providers = {
    aws = aws.tokyo
  }

  project    = var.project
  name       = "tokyo"
  vpc_id     = var.tokyo_vpc_id
  subnet_ids = var.tokyo_db_subnet_ids # tf-tokyo-db-sn5, tf-tokyo-db-sn6
  ecs_sg_id  = var.tokyo_ecs_sg_id     # tf-tokyo-ecs-sg

  create_primary      = false
  create_replica      = false
  replicate_source_db = module.rds_seoul.primary_arn # 크로스 리전은 ARN 필요
}

########################################
# 2. ElastiCache Valkey — 서울 / 도쿄 각 1클러스터 (구성도 기준)
########################################
module "cache_seoul" {
  source = "./modules/elasticache"
  providers = {
    aws = aws.seoul
  }

  project    = var.project
  name       = "seoul"
  vpc_id     = var.seoul_vpc_id
  subnet_ids = var.seoul_db_subnet_ids
  ecs_sg_id  = var.seoul_ecs_sg_id

  num_cache_clusters = 1 # 3주 스코프 → 단일 노드 권장
}

module "cache_tokyo" {
  source = "./modules/elasticache"
  providers = {
    aws = aws.tokyo
  }

  project    = var.project
  name       = "tokyo"
  vpc_id     = var.tokyo_vpc_id
  subnet_ids = var.tokyo_db_subnet_ids
  ecs_sg_id  = var.tokyo_ecs_sg_id

  num_cache_clusters = 1
}

########################################
# 3. S3 — Source(서울) + CRR(도쿄)
########################################
module "s3" {
  source = "./modules/s3"
  providers = {
    aws.source      = aws.seoul
    aws.destination = aws.tokyo
  }

  project                 = var.project
  source_bucket_name      = "${var.project}-source-apne2"
  destination_bucket_name = "${var.project}-crr-apne1"
}

########################################
# 4. AWS Client VPN — 관리자 DB 접근 (서울)
########################################
module "client_vpn" {
  source = "./modules/client-vpn"
  providers = {
    aws = aws.seoul
  }

  project           = var.project
  vpc_id            = var.seoul_vpc_id
  target_subnet_ids = var.seoul_db_subnet_ids
  client_cidr_block = var.vpn_client_cidr
  authorized_cidrs  = var.seoul_db_subnet_cidrs # tf-seoul-db-sn5/sn6 대역만 인가

  server_certificate_arn      = var.vpn_server_cert_arn
  client_root_certificate_arn = var.vpn_client_root_cert_arn
}

########################################
# 5. CloudWatch — 알람(CPU 80% 5분) + SNS + 대시보드 (서울)
########################################
module "cloudwatch_seoul" {
  source = "./modules/cloudwatch"
  providers = {
    aws = aws.seoul
  }

  project          = var.project
  name             = "seoul"
  alarm_email      = var.alarm_email
  ecs_cluster_name = var.seoul_ecs_cluster_name
  ecs_service_name = var.seoul_ecs_service_name
  rds_identifier   = module.rds_seoul.primary_identifier
  alb_arn_suffix   = var.seoul_alb_arn_suffix

  cpu_threshold  = 80  # 운영 결정사항: CPU 80%
  period_seconds = 300 # 5분 지속
}

########################################
# 6. VPC Peering — Site-to-Site VPN 대체
#    구성도에는 Site-to-Site VPN으로 표기, 실제 구현은 피어링
#    서울 VPC ↔ 온프레미스(로 표기된) VPC
########################################
module "peering_seoul_onprem" {
  source = "./modules/vpc-peering"
  providers = {
    aws.requester = aws.seoul
    aws.accepter  = aws.seoul # 온프레미스 VPC가 같은 계정·서울 리전이라고 가정
  }

  project = var.project
  name    = "seoul-onprem"

  requester_vpc_id   = var.seoul_vpc_id
  accepter_vpc_id    = var.onprem_vpc_id
  requester_vpc_cidr = var.seoul_vpc_cidr # 172.16.0.0/16
  accepter_vpc_cidr  = var.onprem_vpc_cidr

  requester_route_table_ids = var.seoul_route_table_ids # tf-seoul-pri-rt34, tf-seoul-db-rt56
  accepter_route_table_ids  = var.onprem_route_table_ids
}

# (선택) 구성도의 Cross-Region VPC Peering — 서울 ↔ 도쿄
# ccrew-tf 가 도쿄 리전에도 region_stack 을 만들었으므로 그대로 재사용 가능하다.
# 사용하려면 tfvars 에 tokyo_route_table_ids 를 채우고 아래 주석을 해제한다.
#
# module "peering_seoul_tokyo" {
#   source = "./modules/vpc-peering"
#   providers = {
#     aws.requester = aws.seoul
#     aws.accepter  = aws.tokyo
#   }
#   project            = var.project
#   name               = "seoul-tokyo"
#   requester_vpc_id   = var.seoul_vpc_id
#   accepter_vpc_id    = var.tokyo_vpc_id
#   requester_vpc_cidr = var.seoul_vpc_cidr   # 172.16.0.0/16
#   accepter_vpc_cidr  = var.tokyo_vpc_cidr   # 172.17.0.0/16
#   accepter_region    = "ap-northeast-1"     # 크로스 리전
#   requester_route_table_ids = var.seoul_route_table_ids  # tf-seoul-pri-rt34, tf-seoul-db-rt56
#   accepter_route_table_ids  = var.tokyo_route_table_ids  # tf-tokyo-pri-rt34, tf-tokyo-db-rt56
# }
