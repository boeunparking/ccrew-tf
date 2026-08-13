# cloud-duck Terraform

서울(Active) + 도쿄(Warm Standby/DR) 구성에서 아래 6개 리소스를 모듈로 관리합니다.
VPC/서브넷/ECS/ALB 등은 기존에 만들어져 있다고 가정하고 ID를 변수로 받습니다.

## 선행 스택 (ccrew-tf)

네트워크는 별도 리포지토리 `ccrew-tf`의 `region_stack` 모듈이 만듭니다.

| | 서울 (`module.seoul`) | 도쿄 (`module.tokyo`) |
|---|---|---|
| 리전 | ap-northeast-2 | ap-northeast-1 |
| VPC CIDR | 172.16.0.0/16 | 172.17.0.0/16 |
| public | tf-seoul-pub-sn1/2 (172.16.0~1.0/24) | tf-tokyo-pub-sn1/2 (172.17.0~1.0/24) |
| ecs | tf-seoul-pri-sn3/4 (172.16.2~3.0/24) | tf-tokyo-pri-sn3/4 (172.17.2~3.0/24) |
| db | tf-seoul-db-sn5/6 (172.16.4~5.0/24) | tf-tokyo-db-sn5/6 (172.17.4~5.0/24) |
| 라우트테이블 | tf-seoul-pub-rt12 / pri-rt34 / db-rt56 | tf-tokyo-pub-rt12 / pri-rt34 / db-rt56 |
| 보안그룹 | tf-seoul-alb-sg / ecs-sg / db-sg | tf-tokyo-alb-sg / ecs-sg / db-sg |

`ccrew-tf`와 이 스택은 **state가 분리**되어 있어 `module.*`로 참조할 수 없습니다.
위 리소스의 실제 ID를 `terraform.tfvars`에 문자열로 채워 넣으세요.

ECS 클러스터/서비스, ALB는 현재 `ccrew-tf` 범위 밖입니다(네트워크만 생성).
CloudWatch 알람용 이름/ARN suffix는 이를 만든 쪽에서 받아와야 합니다.

```
cloud-duck-terraform/
├── providers.tf              # seoul / tokyo provider alias, S3+DynamoDB 백엔드
├── variables.tf
├── main.tf                   # 모듈 6종 조합
├── outputs.tf
├── terraform.tfvars.example
└── modules/
    ├── rds/                  # Primary(Multi-AZ) + Replica + 크로스리전 Replica 겸용
    ├── elasticache/          # Valkey 단일 노드 (cache.t4g.micro)
    ├── s3/                   # Source(서울) + CRR(도쿄), 멀티 프로바이더
    ├── client-vpn/           # 관리자 → DB 접근 (인증서 기반, split tunnel)
    ├── cloudwatch/           # SNS + CPU 80%/5분 알람 + 대시보드
    └── vpc-peering/          # Site-to-Site VPN 대체 (같은/크로스 리전 겸용)
```

## 결정사항 반영

| 항목 | 값 |
|---|---|
| RDS | MySQL 8.0, db.t4g.micro, admin, 10GB, 백업 5일, multi_az=true, Secrets Manager 암호 관리 |
| RDS Replica | db.t4g.micro (서울 동일 리전 + 도쿄 크로스 리전) |
| ElastiCache | Valkey, cache.t4g.micro, 단일 노드(3주 스코프 권장), 리전당 1클러스터 |
| S3 | 서울 Source → 도쿄 CRR (버저닝 필수, IAM 복제 역할 포함) |
| Client VPN | VPN 클라이언트 CIDR(10.200.0.0/22) → DB 서브넷(tf-seoul-db-sn5/6)만 인가, DB SG에 3306 허용 |
| CloudWatch | CPU 80% 5분 지속 알람 (ECS/RDS), FreeStorage, ALB RequestCount, SNS 이메일 |
| Site-to-Site VPN | 구성도 표기만 VPN — 실제는 VPC Peering으로 구현 |

## 사용 방법

```bash
cp terraform.tfvars.example terraform.tfvars   # 실제 ID/ARN으로 수정

terraform init
terraform plan
terraform apply
```

## 주의사항

- **Client VPN 인증서**: 적용 전 ACM에 서버/클라이언트 루트 인증서를 먼저 등록해야 합니다
  (easy-rsa로 생성 → ACM import → ARN을 tfvars에 입력).
- **도쿄 크로스 리전 Replica**는 `replicate_source_db`에 서울 Primary의 **ARN**을 사용합니다
  (모듈에서 자동 연결됨). 서울 Primary 생성 완료 후에 생성됩니다.
- **S3 버킷 이름**은 전역 고유해야 하므로 `main.tf`의 버킷 이름에 팀 식별자를 붙이는 것을 권장합니다.
- **Valkey TLS**: `transit_encryption_enabled = true`라서 앱에서 TLS(rediss://)로 접속해야 합니다.
  불편하면 모듈에서 false로 변경하세요.
- **Client VPN 비용**: 서브넷 연결(association)당 시간 요금이 발생하므로 데모 기간 외에는
  association을 제거해 두는 것이 저렴합니다.
- 크로스 리전 Seoul↔Tokyo 피어링도 같은 `vpc-peering` 모듈로 만들 수 있습니다
  (`main.tf` 하단 주석 예시 참고). `ccrew-tf`가 도쿄 스택도 만들므로 `tokyo_route_table_ids`만
  채우면 바로 사용 가능합니다.
- **DB NACL과 Client VPN**: `ccrew-tf`의 db NACL은 ECS 대역(172.16.2.0/23)에서 오는 3306만
  허용합니다. VPN 클라이언트 대역(10.200.0.0/22)은 NACL에서 차단되므로, 관리자 VPN으로 DB에
  붙으려면 `ccrew-tf` 쪽 db NACL에 VPN CIDR 규칙을 추가해야 합니다(이 스택에서는 못 고칩니다).
- **DB 보안그룹 중복**: `ccrew-tf`가 이미 `tf-seoul-db-sg`(ECS SG → 3306)를 만들고, 이 스택의
  `rds` 모듈도 자체 SG(`cloud-duck-seoul-db-sg`)를 만듭니다. RDS에는 후자만 붙으므로 동작에는
  문제가 없지만 SG가 하나 놀게 됩니다.
