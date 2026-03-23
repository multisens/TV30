FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    libssl-dev \
    libc-ares-dev \
    uuid-dev \
    libwebsockets-dev \
    libcjson-dev \
    libjson-c-dev \
    libhiredis-dev \
    python3 \
    python3-pip \
    redis-tools \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install redis

WORKDIR /tmp

RUN wget https://mosquitto.org/files/source/mosquitto-2.0.22.tar.gz && \
    tar -xzf mosquitto-2.0.22.tar.gz && \
    cd mosquitto-2.0.22 && \
    make WITH_WEBSOCKETS=yes && \
    make install && \
    ldconfig

COPY plugin/src/ /tmp/src/
COPY plugin/include/ /tmp/include/

RUN gcc -fPIC -shared -o /usr/local/lib/mosquitto_plugin.so \
    /tmp/src/mosquitto_plugin.c \
    /tmp/src/schema_validator.c \
    /tmp/src/response_time_tester.c \
    /tmp/src/authorize.c \
    -ljson-c -lhiredis -I/tmp/mosquitto-2.0.22/include -I/tmp/include

RUN useradd -r -s /bin/false mosquitto && \
    mkdir -p /mosquitto/config /mosquitto/data /mosquitto/log && \
    chown -R mosquitto:mosquitto /mosquitto

COPY plugin/config/mosquitto.conf plugin/config/schemas.json plugin/config/acl.json plugin/config/userData.json /mosquitto/config/
COPY infra/migrate_to_redis.py /usr/local/bin/migrate_to_redis.py
COPY infra/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 1883

USER mosquitto

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
