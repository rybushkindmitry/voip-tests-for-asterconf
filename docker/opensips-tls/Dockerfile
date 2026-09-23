# opensips/opensips:3.6 + TLS-модули (в базовом образе их нет).
# Пакеты из apt.opensips.org:
#   opensips-tls-module        -> proto_tls.so   (TLS-транспорт)
#   opensips-tlsmgm-module     -> tls_mgm.so     (сертификаты/домены)
#   opensips-tls-openssl-module-> tls_openssl.so (SSL-бэкенд для tls_mgm)
FROM opensips/opensips:3.6

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        opensips-tls-module \
        opensips-tls-openssl-module \
        opensips-tlsmgm-module \
 && rm -rf /var/lib/apt/lists/*
