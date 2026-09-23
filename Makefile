# Образы публикуются на Docker Hub (make push-images, multi-arch: amd64 + arm64),
# чтобы демо поднималось на любой машине без локальной сборки.
HUB          ?= drybushkin
CI_IMAGE     := $(HUB)/voip-tests-ci:latest
SIPP_IMAGE   := $(HUB)/voip-tests-sipp:3.7.7
SIPSSERT_IMG := opensips/sipssert:latest
DOCKER_SOCK  := /var/run/docker.sock
IMAGES       := $(CI_IMAGE) $(SIPP_IMAGE) $(SIPSSERT_IMG) jambonz/rtpengine:14.1.1.8-jambonz13 \
                $(HUB)/pjsua-for-sipssert:latest $(HUB)/voip-tests-opensips-tls:3.6
OPENIPS_TLS_IMAGE := $(HUB)/voip-tests-opensips-tls:3.6

ENV ?= test

.PHONY: help pull push-images sipp-image ci-image opensips-tls-image provision ci ci-deploy demo report clean

help: ## Список целей
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

pull: ## Пре-тянуть все образы с Docker Hub (multi-arch amd64+arm64; дальше — офлайн)
	@for img in $(IMAGES); do docker pull $$img || exit 1; done

push-images: ## Собрать и запушить ci+sipp (multi-arch) и opensips-tls (только amd64) на Docker Hub (нужен docker login)
	docker buildx build --platform linux/amd64,linux/arm64 -t $(CI_IMAGE) --push docker/ci
	docker buildx build --platform linux/amd64,linux/arm64 -t $(SIPP_IMAGE) --push docker/sipp
	# opensips-tls: amd64-only — базовый opensips/opensips:3.6 и apt.opensips.org
	# не публикуют arm64 (на Apple Silicon работает под эмуляцией — для тестов достаточно)
	docker buildx build --platform linux/amd64 -t $(OPENIPS_TLS_IMAGE) --push docker/opensips-tls

sipp-image: ## Собрать образ SIPp 3.7.7 локально (нативная архитектура хоста)
	docker build -t $(SIPP_IMAGE) docker/sipp

ci-image: ## Собрать образ CI-джобы локально
	docker build -t $(CI_IMAGE) docker/ci

opensips-tls-image: ## Собрать локально opensips:3.6 + TLS-модули (в Hub — push-images)
	docker build -t $(OPENIPS_TLS_IMAGE) docker/opensips-tls

provision: ## Прогнать ansible-плейбук без CI (деплой SUT + подготовка тестов + прогон sipssert); окружение — ENV=<test|dev|stage|prod>, инвентарь — ansible/inventories/$(ENV)/
	docker run --rm \
		-v $(DOCKER_SOCK):$(DOCKER_SOCK) \
		-v $(CURDIR):$(CURDIR) -w $(CURDIR) \
		-e ENV="$(ENV)" \
		-e SKIP_KNOWN_FAILING="$(SKIP_KNOWN_FAILING)" \
		-e CI_PROJECT_DIR="$(CURDIR)" \
		$(CI_IMAGE) ansible-playbook -i ansible/inventories/$(ENV)/inventory.ini ansible/playbook.yml

ci: ## Локальный pipeline: gitlab-ci-local test (SKIP_KNOWN_FAILING=enable make ci — зелёный вариант)
	gitlab-ci-local test \
		--variable SKIP_KNOWN_FAILING=$(SKIP_KNOWN_FAILING) \
		--variable HOST_WORKSPACE=$(CURDIR) \
		--volume $(DOCKER_SOCK):$(DOCKER_SOCK) \
		--volume $(CURDIR):$(CURDIR)

ci-deploy: ## Локальный запуск ручной джобы deploy (заглушка: gitlab-ci-local deploy)
	gitlab-ci-local deploy \
		--variable SKIP_KNOWN_FAILING=$(SKIP_KNOWN_FAILING) \
		--variable HOST_WORKSPACE=$(CURDIR) \
		--volume $(DOCKER_SOCK):$(DOCKER_SOCK) \
		--volume $(CURDIR):$(CURDIR)

demo: ## make demo SET=call_to_trunk — прогнать один набор sipssert (нужен предварительный make provision)
	rm -f $(CURDIR)/build/tests/logs/latest
	docker run --rm \
		-v $(DOCKER_SOCK):$(DOCKER_SOCK) \
		-v $(CURDIR)/build/tests:$(CURDIR)/build/tests -w $(CURDIR)/build/tests \
		$(SIPSSERT_IMG) $(SET)

report: ## Человекочитаемая сводка report.xml
	@python3 scripts/report.py report.xml

clean: ## Удалить артефакты сборки
	rm -rf build report.xml
