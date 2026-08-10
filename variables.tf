# variables.tf (루트)
variable "ecs_tier_cidr" {
  description = "ECS 티어 서브넷 전체를 요약하는 상위 CIDR (sn2+sn3)"
  type        = string
  default     = "10.0.2.0/23"
}