FROM postgres:18

RUN apt-get update \
    && apt-get install -y --no-install-recommends cron curl jq tzdata util-linux \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 iniciar-backup.sh backup.sh /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/iniciar-backup.sh"]
