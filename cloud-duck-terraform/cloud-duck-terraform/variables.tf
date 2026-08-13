########################################
# 공통
########################################
variable "project" {
  description = "프로젝트 이름"
  type        = string
  default     = "cloud-duck"
}

########################################
# 서울 리전 (Active) — ccrew-tf 의 module "seoul" (region_stack) 이 만든 리소스 참조
# seoul-vpc: 172.16.0.0/16
#
# ccrew-tf 는 별도 state 이므로 여기서는 module.* 로 참조할 수 없고,
# 실제 ID 값을 terraform.tfvars 에 넣어 준다.
#   ccrew-tf 의 region_stack outputs: vpc_id / igw_id / subnet_ids(map) / alb_sg_id / ecs_sg_id / db_sg_id
########################################
variable "seoul_vpc_id" {
  description = "서울 seoul-vpc ID (ccrew-tf module.seoul.vpc_id)"
  type        = string
}

variable "seoul_db_subnet_ids" {
  description = "서울 DB 서브넷 (tf-seoul-db-sn5 172.16.4.0/24, tf-seoul-db-sn6 172.16.5.0/24)"
  type        = list(string)
}

variable "seoul_private_subnet_ids" {
  description = "서울 프라이빗(ECS) 서브넷 (tf-seoul-pri-sn3 172.16.2.0/24, tf-seoul-pri-sn4 172.16.3.0/24)"
  type        = list(string)
}

variable "seoul_ecs_sg_id" {
  description = "서울 tf-seoul-ecs-sg (RDS/Redis 인바운드 소스)"
  type        = string
}

variable "seoul_db_subnet_cidrs" {
  description = "DB 서브넷 CIDR (Client VPN 인가 규칙용)"
  type        = list(string)
  default     = ["172.16.4.0/24", "172.16.5.0/24"]
}

########################################
# 도쿄 리전 (Warm Standby) — ccrew-tf 의 module "tokyo" (region_stack) 이 만든 리소스 참조
# tokyo-vpc: 172.17.0.0/16
########################################
variable "tokyo_vpc_id" {
  description = "도쿄 tokyo-vpc ID (ccrew-tf module.tokyo.vpc_id)"
  type        = string
}

variable "tokyo_db_subnet_ids" {
  description = "도쿄 DB 서브넷 (tf-tokyo-db-sn5 172.17.4.0/24, tf-tokyo-db-sn6 172.17.5.0/24)"
  type        = list(string)
}

variable "tokyo_ecs_sg_id" {
  description = "도쿄 tf-tokyo-ecs-sg"
  type        = string
}

variable "tokyo_route_table_ids" {
  description = "도쿄 측 라우트 테이블 (tf-tokyo-pri-rt34, tf-tokyo-db-rt56) — 크로스 리전 피어링 사용 시에만 필요"
  type        = list(string)
  default     = []
}

########################################
# VPC Peering (Site-to-Site VPN 대체)
# 온프레미스로 표기된 VPC ↔ 서울 VPC
########################################
variable "onprem_vpc_id" {
  description = "온프레미스로 표기된 VPC ID (같은 계정/서울 리전 가정)"
  type        = string
}

variable "onprem_vpc_cidr" {
  description = "온프레미스 VPC CIDR"
  type        = string
  default     = "10.100.0.0/16"
}

variable "seoul_vpc_cidr" {
  description = "서울 VPC CIDR (ccrew-tf var.vpc_cidr_seoul 과 동일해야 함)"
  type        = string
  default     = "172.16.0.0/16"
}

variable "tokyo_vpc_cidr" {
  description = "도쿄 VPC CIDR (ccrew-tf var.vpc_cidr_tokyo 과 동일해야 함)"
  type        = string
  default     = "172.17.0.0/16"
}

variable "seoul_route_table_ids" {
  description = "서울 측 피어링 경로를 추가할 라우트 테이블 (tf-seoul-pri-rt34, tf-seoul-db-rt56 등)"
  type        = list(string)
}

variable "onprem_route_table_ids" {
  description = "온프레미스 VPC 측 라우트 테이블"
  type        = list(string)
}

########################################
# Client VPN
########################################
variable "vpn_client_cidr" {
  description = "VPN 클라이언트 CIDR (VPC와 겹치지 않아야 함)"
  type        = string
  default     = "10.200.0.0/22"
}

variable "vpn_server_cert_arn" {
  description = "ACM 서버 인증서 ARN"
  type        = string
}

variable "vpn_client_root_cert_arn" {
  description = "ACM 클라이언트 루트(상호 인증) 인증서 ARN"
  type        = string
}

########################################
# CloudWatch / 알람
########################################
variable "alarm_email" {
  description = "SNS 알람 수신 이메일"
  type        = string
  default     = "team@cloud-duck.io"
}

########################################
# 아래 ECS / ALB 값은 ccrew-tf(region_stack) 범위 밖이다.
# 현재 ccrew-tf 는 네트워크(VPC/Subnet/RT/SG/NACL)만 생성하므로
# ECS 클러스터·서비스·ALB 를 만든 쪽에서 실제 이름을 받아 채워야 한다.
########################################
variable "seoul_ecs_cluster_name" {
  description = "서울 ECS 클러스터 이름 (ccrew-tf 외부에서 생성)"
  type        = string
  default     = "cloud-duck-seoul"
}

variable "seoul_ecs_service_name" {
  description = "서울 ECS 서비스 이름 (ccrew-tf 외부에서 생성)"
  type        = string
  default     = "cloud-duck-app"
}

variable "seoul_alb_arn_suffix" {
  description = "ALB ARN suffix (app/xxx/yyy) — RequestCount 알람용. 빈 값이면 ALB 알람은 만들지 않음"
  type        = string
  default     = ""
}
