# 테스트 이미지 빌드 & ECR 푸시
# 주의: terraform apply 로 ECR 리포지토리가 먼저 생성돼 있어야 함
#
# 사용법:  .\push.ps1

$ErrorActionPreference = "Stop"

$AccountId = "242071452403"
$Region    = "ap-northeast-2"
$Registry  = "$AccountId.dkr.ecr.$Region.amazonaws.com"
$Tag       = "latest"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==> ECR 로그인" -ForegroundColor Cyan
aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $Registry
if ($LASTEXITCODE -ne 0) { throw "ECR 로그인 실패" }

# Fargate 기본 플랫폼이 X86_64 라 --platform 을 명시해야 함
foreach ($svc in @(
    @{ Name = "web";   Repo = "tf-web-ecr" },
    @{ Name = "batch"; Repo = "tf-batch-ecr" }
)) {
    $image = "$Registry/$($svc.Repo):$Tag"
    $ctx   = Join-Path $here $svc.Name

    Write-Host "==> build $image" -ForegroundColor Cyan
    docker build --platform linux/amd64 -t $image $ctx
    if ($LASTEXITCODE -ne 0) { throw "$($svc.Name) 빌드 실패" }

    Write-Host "==> push $image" -ForegroundColor Cyan
    docker push $image
    if ($LASTEXITCODE -ne 0) { throw "$($svc.Name) 푸시 실패" }
}

Write-Host "==> 완료. ECS 가 재시도 중이면 몇 분 내에 태스크가 올라옵니다." -ForegroundColor Green
