# Образ CI-джобы: ansible + docker-cli.
# Джоба запускает ansible-playbook (connection: local), а ansible запускает
# sipssert через смонтированный /var/run/docker.sock — поэтому в образе
# нужен docker CLI.
#
# В проде: образ берётся из приватного registry и внутри уже есть всё нужное
# (ansible, vault-клиент, docker CLI и т.п.).
FROM alpine:3.20

RUN apk add --no-cache ansible docker-cli bash
