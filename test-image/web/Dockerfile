# 테스트용 최소 웹 이미지 - 3000 포트로 응답하고 /health 로 200 반환
# Docker Hub rate limit 걸리면 아래 줄을 public.ecr.aws/nginx/nginx:alpine 으로 교체
FROM nginx:alpine

COPY default.conf /etc/nginx/conf.d/default.conf

EXPOSE 3000
