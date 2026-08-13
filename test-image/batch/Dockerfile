# 테스트용 최소 배치 워커 이미지
# 포트도 ALB 연결도 없으므로 "종료되지 않고 로그를 남기는 것"만 하면 됨
# (컨테이너가 바로 끝나면 ECS 가 죽은 것으로 보고 태스크를 계속 재시작함)
FROM alpine:latest

CMD ["sh", "-c", "while true; do echo \"[batch] alive $(date -u +%Y-%m-%dT%H:%M:%SZ)\"; sleep 60; done"]
