# syntax=docker/dockerfile:1.7
#
# Builds this Keycloak fork from source and packages it the same way the
# upstream image does (quarkus/container/Dockerfile). Build from the repo root:
#
#     docker build -f docker/Dockerfile -t keycloak-custom .
#
# or simply `docker compose build` from the docker/ directory.

ARG KEYCLOAK_VERSION=26.7.3
ARG KC_DB=postgres
# Comma-separated Keycloak features to enable at build time (scim-api is a
# preview feature required by the identity-service realm).
ARG KC_FEATURES=scim-api

# ---------------------------------------------------------------------------
# Stage 1: compile the server distribution (quarkus/dist) with Maven.
# ---------------------------------------------------------------------------
FROM eclipse-temurin:21-jdk AS builder

ENV MAVEN_OPTS="-Xmx2g -Dmaven.repo.local=/root/.m2/repository"
# The admin client generates its API from openapi.json with Kiota (a .NET tool);
# the builder image has no ICU libraries, so run .NET in invariant-globalization mode.
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
WORKDIR /src

COPY . .

# The admin/account consoles are built with node + pnpm downloaded by
# frontend-maven-plugin, so the build needs network access.
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw -B -ntp \
        -pl quarkus/deployment,quarkus/dist -am \
        -DskipTests -DskipProtoLock=true \
        clean install \
    && mkdir -p /out \
    && cp quarkus/dist/target/keycloak-*.tar.gz /out/

# ---------------------------------------------------------------------------
# Stage 2: unpack the distribution and prepare a minimal UBI rootfs
# (mirrors quarkus/container/Dockerfile).
# ---------------------------------------------------------------------------
FROM registry.access.redhat.com/ubi9 AS ubi-micro-build

RUN dnf install -y tar gzip

COPY --from=builder /out/keycloak-*.tar.gz /tmp/keycloak/

RUN cd /tmp/keycloak && \
    tar -xf /tmp/keycloak/keycloak-*.tar.gz && \
    rm /tmp/keycloak/keycloak-*.tar.gz && \
    mv /tmp/keycloak/keycloak-* /opt/keycloak && \
    mkdir -p /opt/keycloak/data && \
    chmod -R g+rwX /opt/keycloak

COPY quarkus/container/ubi-null.sh /tmp/
RUN bash /tmp/ubi-null.sh java-21-openjdk-headless glibc-langpack-en findutils

# ---------------------------------------------------------------------------
# Stage 3: runtime image.
# ---------------------------------------------------------------------------
FROM registry.access.redhat.com/ubi9-micro

ARG KEYCLOAK_VERSION
ARG KC_DB
ARG KC_FEATURES

ENV LANG=en_US.UTF-8
ENV KC_RUN_IN_CONTAINER=true

COPY --from=ubi-micro-build /tmp/null/rootfs/ /
COPY --from=ubi-micro-build --chown=1000:0 /opt/keycloak /opt/keycloak

RUN echo "keycloak:x:0:root" >> /etc/group && \
    echo "keycloak:x:1000:0:keycloak user:/opt/keycloak:/sbin/nologin" >> /etc/passwd

USER 1000

# Pre-build an optimized server so `start --optimized` boots fast.
# Build-time options (db, health, metrics) are fixed here; runtime options
# (hostname, db url/credentials, import) come from the environment.
ENV KC_DB=${KC_DB} \
    KC_FEATURES=${KC_FEATURES} \
    KC_HEALTH_ENABLED=true \
    KC_METRICS_ENABLED=true
RUN /opt/keycloak/bin/kc.sh build

EXPOSE 8080
EXPOSE 8443
EXPOSE 9000

ENTRYPOINT [ "/opt/keycloak/bin/kc.sh" ]
CMD [ "start", "--optimized" ]

LABEL org.opencontainers.image.title="Keycloak (custom build)" \
      org.opencontainers.image.version=${KEYCLOAK_VERSION} \
      org.opencontainers.image.source="https://github.com/keycloak/keycloak"
