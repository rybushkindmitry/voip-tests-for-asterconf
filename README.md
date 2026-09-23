# voip-tests-for-asterconf — демо: автоматизированное тестирование телефонии

Демо-проект к докладу (Asterconf): как автоматизировать тестирование телефонии
связкой **GitLab CI → Ansible → Sipssert**. Репозиторий самодостаточен: в нём есть и
тестируемая система (мини-gateway на OpenSIPS + rtpengine), и тесты, и вся
обвязка. Структура файлов повторяет типовой production-репозиторий SBC — разница только
в масштабе конфигов.

```
   git push ──▶ GitLab CI (test + deploy:manual) ──▶ ansible-playbook ──▶ Sipssert
                report.xml (JUnit) ◀── report.xml ◀── opensips+rtpengine+sipp
```

Стадия `deploy` в демо — ручная джоба-заглушка (кнопка в UI GitLab; локально:
`make ci-deploy`). В проде деплой на каждую ноду — отдельная ручная джоба
(`--limit <node>`, serial: 1 для SBC-пар).

Локально pipeline выполняет `gitlab-ci-local`: читает настоящий
`.gitlab-ci.yml` и запускает джобы в docker — GitLab-сервер не нужен.

## Структура проекта

| Папка | Описание |
|---|---|
| `opensips/` | jinja-шаблон конфига мини-gateway (`opensips.cfg.j2`) — SUT; рендерится ansible'ом при деплое |
| `rtpengine/` | jinja-шаблон конфига медиа-сервера (`rtpengine.conf.j2`) — вторая половина SUT |
| `tests/` | наборы sipssert-тестов: `<набор>/<юнит-тест>/scenario.yml` + XML-сценарии (SIPp / pjsua) |
| `ansible/` | плейбук, `inventories/<env>/` — инвентари окружений (test — localhost, dev/stage/prod — SSH-схема), `group_vars/all.yml` (базовые значения SUT и стенда), `vars/` — переопределения окружений, `files/tls/` — self-signed сертификаты SBC (TLS-тесты) и две роли: `gateway` — рендер и деплой конфигов SUT, `test` — раскладка тестов, рендеринг `run.yml` и прогон sipssert |
| `gitlab-ci/` | описание CI-джоб: `test` и ручная заглушка `deploy`; подключаются из `.gitlab-ci.yml` (`include`) |
| `docker/` | Dockerfile'ы: `ci/` — образ CI-джобы (ansible + docker-cli), `sipp/` — сборка SIPp 3.7; образ pjsua собирается из внешнего репо `rybushkindmitry/pjsua-for-sipssert` |
| `scripts/` | `report.py` — человекочитаемая сводка JUnit-отчёта (`make report`) |
| `build/` | рабочий каталог деплоя — генерируется ansible'ом, в git не попадает |

Как в production-репозитории, стенды разделены по окружениям: переменная
`ENV` (test/dev/stage/prod, по умолчанию `test`) выбирает инвентарь
`ansible/inventories/<env>/inventory.ini` (test — localhost, dev/stage/prod —
SSH-схема хостов) и файл `ansible/vars/<env>_vars.yml`, который подключается
плейбуком через `include_vars` и точечно переопределяет базовые значения из
`group_vars/all.yml` (пути деплоя, медиа-порты SIPp, адрес control-сокета
rtpengine). Локальный прогон выполняется в окружении `test`; `dev`/`stage`/
`prod` описывают серверные стенды — файлы показывают схему, но локально
не исполняются.

## Что тестируется (SUT)

Мини-gateway (рендерится из `opensips/opensips.cfg.j2` + `rtpengine/rtpengine.conf.j2`):

- INVITE от АТС (`192.168.51.5`) с заголовком `X-gwid` → маршрутизация на
  транк (`198.51.100.5:5081`), медиа через rtpengine;
- INVITE от транка по TLS (`5061`, self-signed сертификаты из `ansible/files/tls`) → АТС (UDP); SRTP на внешнем плече терминирует rtpengine;
- всё остальное → `403 Forbidden`.

OpenSIPS и rtpengine запускаются в host-режиме на одном IP — как в проде, где
SBC и медиа-сервер совмещены на ноде. SIP-эндпоинты (SIPp и pjsua) видят SBC по адресам
`192.168.51.1` / `198.51.100.1` (gateway-адреса bridge-сетей).

> Сертификаты в `ansible/files/tls/` — демонстрационные self-signed: ключи
> сгенерированы специально для этого демо и используются только тестами.
> В production-репозитории сертификаты берут из Vault, приватные ключи в git не попадают.

## Тесты (`tests/`)

| Набор | Что проверяет |
|---|---|
| `config_check` | валидность конфига: `opensips -C` |
| `call_to_trunk` | звонок АТС → транк: 01 — happy path с проверкой RTP (битовый паттерн `rtp_stream`, UAS эхо-отражает `-rtp_echo`, UAC сверяет); 02 — то же с re-INVITE от АТС (пересогласование SDP + RTP после него) |
| `call_from_trunk` | звонок транк → АТС: 01 — happy path с проверкой RTP, BYE от АТС; 02 — in-dialog BYE из внешней сети; 03 — re-INVITE от транка (пересогласование SDP + RTP после него) |
| `unauthorized` | INVITE от «хакера» → 403 |
| `tls_from_trunk` | TLS-звонки от транка (pjsua-test): 01 — SIP-over-TLS → АТС (UDP), RTP-эхо + проверка Record-Route; 02 — то же с обязательным SDES-SRTP (rtpengine терминирует SRTP) |
| `broken_check` | заведомо падающий (нет заголовка в 200 OK) — демонстрация красного pipeline |

Каждый юнит-тест — каталог с `scenario.yml` (задачи: rtpengine, opensips,
sipp-/pjsua-эндпоинты) и XML-сценариями. Sipssert сам поднимает docker-сети
и контейнеры для каждого юнит-теста.

Две находки, которые полезно знать при работе с SIPp 3.7 и прокси:

1. SIPp 3.7 «RTP check» пропускает проверку, если UAC не отправил **ни одного**
   пакета (0/0 — вакуумный успех). В изолированных сетях демо это означает:
   сломанный rtpengine ловится только тестом с реальным потоком пакетов
   (см. чувствительность ниже).
2. `[last_Record-Route:]` в ACK/BYE (запросах) подставляет заголовок с именем
   `Record-Route` — и прокси его игнорирует (нужен `Route:`). Правильный
   паттерн для in-dialog запросов: `R-URI [next_url]` + `Route: <sip:...;lr>`.

## Быстрый старт

```bash
brew install gitlab-ci-local   # один раз
make pull                      # пре-тянуть все образы с Docker Hub (multi-arch amd64+arm64, дальше — офлайн)
make ci                        # полный pipeline; broken_check красный -> job FAIL
SKIP_KNOWN_FAILING=enable make ci   # зелёный прогон (без broken_check)
make ci-deploy                 # ручная джоба deploy (заглушка, как кнопка в UI)
make report                    # сводка report.xml
```

Свои образы (`ci`, `sipp`, `pjsua`) лежат на Docker Hub, сборка на новой машине не нужна.
Обновить их в registry: `docker login` + `make push-images` (multi-arch:
linux/amd64 + linux/arm64); `make ci-image` / `make sipp-image` — локальная
сборка под архитектуру хоста, если правите Dockerfile'ы.

Точечные запуски:

```bash
make provision                 # ansible: деплой + тесты без CI-обёртки
make demo SET=call_to_trunk    # один набор sipssert
```

Требования: docker, make, python3 (только для `make report`),
gitlab-ci-local. Образы — multi-arch (amd64 + arm64), проверено на
macOS + Apple Silicon и на Linux x86_64.

## Чувствительность RTP-проверки

Закомментируйте `-rtp_echo` у задачи `sipp_uas_trunk_rtp` в
`ansible/roles/test/templates/config.yml.j2` — имитация односторонней аудиосвязи.
`call_to_trunk/01` падает (SIPp exit 253: пакеты отправлены, эхо не вернулось),
pipeline красный. Верните флаг — зелёный.

## Как добавить свой тест

1. `mkdir -p tests/<набор>/<юнит-тест>` и создайте `scenario.yml` (задачи:
   `rtpengine`, `opensips`, один из sipp-шаблонов) и XML-сценарий SIPp.
2. Шаблоны задач — в `ansible/roles/test/templates/config.yml.j2`, значения — в
   `ansible/group_vars/all.yml` (адреса, сети, эндпоинты — общие с деплоем SUT),
   `ansible/vars/<env>_vars.yml` (переопределения окружений) и
   `ansible/roles/test/defaults/main.yml` (образы, порты SIPp).
3. Ansible раскладывает всё содержимое `tests/` в `build/tests` и генерирует
   `run.yml` — набор появится в сборке.
4. Исполняемый список наборов задан явно: добавьте имя набора в список `tests:`
   в `ansible/roles/test/templates/run.yml.j2` (в проде тот же приём — набор
   попадает в run.yml осознанно, а не автопоиском).

## Здесь vs production-окружение

| Здесь | В production-окружении |
|---|---|
| `gitlab-ci/test.yml` | та же джоба на выделенном раннере с SSH-доступом к тестовой ноде |
| `gitlab-ci/deploy.yml` (заглушка-кнопка) | ручные джобы деплоя на каждую ноду (+ protected environment, approvals) |
| `ansible/inventories/test/` (localhost, connection: local) | те же плейбуки против реальных SSH-нод из инвентарей dev/stage/prod |
| `ansible/roles/test/tasks/main.yml` | та же роль + Vault-секреты, приватный registry (забор отчёта через `fetch` уже как в проде) |
| `make ci` (gitlab-ci-local) | pipeline на раннере `tags: [voip-test-runner]` |
| публичные образы | приватный registry, сертификаты из Vault |

## Как превратить в production-пайплайн

1. `ansible/inventories/` — инвентари уже разделены по окружениям: `test` —
   localhost (так работает демо), `dev`/`stage`/`prod` — SSH-схема хостов;
   в продовом репозитории останется подставить реальные адреса.
2. `gitlab-ci/test.yml` — добавить `tags: [voip-test-runner]`, образ из приватного
   registry, переменные окружения; `DEPLOY_DIR` передать переменной окружения
   (плейбук читает её первой). Заглушку `gitlab-ci/deploy.yml` развернуть в
   ручные джобы деплоя на каждую ноду (`needs: [test]`, `when: manual`,
   `--limit <node>`).
3. Роль `test` — вернуть продовые шаги: Vault-секреты, TLS-сертификаты в
   docker volume. Забор отчёта (`fetch`) менять не нужно — он уже
   production-совместимый, при переходе обновляется только `inventory.ini`.
4. Направления расширения тестов: нагрузочные (`performance`).

## Полезное

- Sipssert (движок сценариев): https://github.com/OpenSIPS/sipssert
- Синтаксис RTP check SIPp 3.7: `sipp -h` / исходники sipp
