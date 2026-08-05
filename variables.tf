# variables.tf (루트)
variable "db_tier_cidr" {
  description = "DB 티어 서브넷 전체를 요약하는 상위 CIDR (sn4+sn5)"
  type        = string
  default     = "10.0.4.0/23"
}