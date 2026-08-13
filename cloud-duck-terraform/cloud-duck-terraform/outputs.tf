output "rds_seoul_primary_endpoint" {
  description = "서울 RDS Primary 엔드포인트"
  value       = module.rds_seoul.primary_endpoint
}

output "rds_seoul_replica_endpoint" {
  description = "서울 RDS Read Replica 엔드포인트"
  value       = module.rds_seoul.replica_endpoint
}

output "rds_tokyo_replica_endpoint" {
  description = "도쿄 크로스 리전 Replica 엔드포인트"
  value       = module.rds_tokyo_replica.replica_endpoint
}

output "rds_secret_arn" {
  description = "Secrets Manager 시크릿 ARN (admin 암호)"
  value       = module.rds_seoul.secret_arn
}

output "valkey_seoul_endpoint" {
  value = module.cache_seoul.primary_endpoint
}

output "valkey_tokyo_endpoint" {
  value = module.cache_tokyo.primary_endpoint
}

output "s3_source_bucket_arn" {
  value = module.s3.source_bucket_arn
}

output "s3_crr_bucket_arn" {
  value = module.s3.destination_bucket_arn
}

output "client_vpn_endpoint_dns" {
  description = "관리자 VPN 접속 DNS"
  value       = module.client_vpn.endpoint_dns
}

output "alarm_sns_topic_arn" {
  value = module.cloudwatch_seoul.sns_topic_arn
}

output "peering_seoul_onprem_id" {
  value = module.peering_seoul_onprem.peering_connection_id
}
