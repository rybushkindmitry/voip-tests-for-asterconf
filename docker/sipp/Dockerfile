# Образ SIPp 3.7.7, собранный из исходников (нужен для RTP check — SIPp >= 3.7).
# Публикуется на Docker Hub как multi-arch (linux/amd64 + linux/arm64):
# `make push-images`. Публичные образы SIPp 3.7 — amd64-only, а под Apple Silicon
# amd64-бинарь через Rosetta падает (epoll EPERM) — поэтому arm64 собирается нативно.
# В проде: используется свой образ из приватного registry (registry.example.com/voip/sipp:3.7.5).
FROM debian:bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake wget ca-certificates \
        libssl-dev libpcap-dev libncurses-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q https://github.com/SIPp/sipp/releases/download/v3.7.7/sipp-3.7.7.tar.gz \
    && tar xzf sipp-3.7.7.tar.gz \
    && cd sipp-3.7.7 \
    && cmake . -DUSE_SSL=1 -DUSE_PCAP=1  \
    && make -j"$(nproc)" \
    && install -m 755 sipp /usr/local/bin/sipp

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        libssl3 libpcap0.8 libncurses6 libncursesw6 zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/bin/sipp /usr/local/bin/sipp

ENTRYPOINT ["sipp"]
