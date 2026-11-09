FROM postgres:16

# Instalación de dependencias y Patroni con soporte etcd3
RUN apt update \
    && apt install -y --no-install-recommends python3 python3-pip python3-psycopg2 gosu gettext \
    && pip3 install --no-cache-dir --break-system-packages "patroni[etcd3]" \
    && apt purge -y python3-pip \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

COPY config/patroni.yml /etc/patroni/patroni.yml
COPY scripts/init-cluster.sh /usr/local/bin/init-cluster.sh
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 755 /usr/local/bin/init-cluster.sh /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT [ "/usr/local/bin/docker-entrypoint.sh" ]
