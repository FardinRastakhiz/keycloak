# ---- Stage 1: Build the Keycloak distribution from source using Maven ----
FROM maven:3.9.15-eclipse-temurin-21 AS maven-build

ARG MAVEN_CLI_OPTS="-DskipTests --no-transfer-progress"

# libicu74 is required by the Kiota .NET tool used during the JS (admin-client) build.
# The maven:3.9-eclipse-temurin-21 image is based on Ubuntu 24.04 where the package is libicu74.
RUN apt-get update -qq && apt-get install -y --no-install-recommends libicu74 && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy the full source tree into the build context
COPY . .

# Build only the distribution module and its transitive dependencies,
# then unpack the resulting archive to a well-known path for the next stage.
RUN ./mvnw ${MAVEN_CLI_OPTS} -pl quarkus/dist -am clean package && \
    mkdir -p /build/keycloak && \
    tar -xzf quarkus/dist/target/keycloak-*.tar.gz -C /build/keycloak --strip-components=1 && \
    mkdir -p /build/keycloak/data && \
    chmod -R g+rwX /build/keycloak

# ---- Stage 2: Runtime image with a prebuilt optimized Keycloak distribution ----
FROM eclipse-temurin:21-jre-jammy
ENV LANG=C.UTF-8

# Flag for determining app is running in container
ENV KC_RUN_IN_CONTAINER=true

COPY --from=maven-build --chown=1000:0 /build/keycloak /opt/keycloak

RUN useradd --uid 1000 --gid 0 --home-dir /opt/keycloak --shell /usr/sbin/nologin keycloak

USER 1000

RUN /opt/keycloak/bin/kc.sh build --db=postgres --health-enabled=true --metrics-enabled=true

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=5 CMD ["/bin/bash", "-c", "{ printf 'HEAD /health/ready HTTP/1.0\\r\\n\\r\\n' >&0; grep 'HTTP/1.0 200'; } 0<>/dev/tcp/localhost/9000"]

EXPOSE 8080
EXPOSE 8443
EXPOSE 9000

ENTRYPOINT [ "/opt/keycloak/bin/kc.sh" ]

# common labels
ARG KEYCLOAK_VERSION=999.0.0-SNAPSHOT
ARG KEYCLOAK_URL="https://www.keycloak.org/"
ARG KEYCLOAK_TAGS="keycloak security identity"
ARG KEYCLOAK_MAINTAINER=${KEYCLOAK_URL}
ARG KEYCLOAK_VENDOR=${KEYCLOAK_MAINTAINER}
ARG BUILD_DATE=""
ARG VCS_REF=""

LABEL maintainer=${KEYCLOAK_MAINTAINER} \
      vendor=${KEYCLOAK_VENDOR} \
      version=${KEYCLOAK_VERSION} \
      url=${KEYCLOAK_URL} \
      io.openshift.tags=${KEYCLOAK_TAGS} \
      release="" \
      vcs-ref=${VCS_REF} \
      com.redhat.build-host="" \
      com.redhat.component="" \
      com.redhat.license_terms=""

# server specific
ARG KEYCLOAK_SERVER_DISPLAY_NAME="Keycloak Server"
ARG KEYCLOAK_SERVER_IMAGE_NAME="keycloak"
ARG KEYCLOAK_SERVER_DESCRIPTION="${KEYCLOAK_SERVER_DISPLAY_NAME} Image"

LABEL name=${KEYCLOAK_SERVER_IMAGE_NAME} \
      description=${KEYCLOAK_SERVER_DESCRIPTION} \
      summary=${KEYCLOAK_SERVER_DESCRIPTION} \
      io.k8s.display-name=${KEYCLOAK_SERVER_DISPLAY_NAME} \
      io.k8s.description=${KEYCLOAK_SERVER_DESCRIPTION}

# oci
ARG KEYCLOAK_SOURCE="https://github.com/keycloak/keycloak"
ARG KEYCLOAK_DOCS=${KEYCLOAK_URL}documentation

LABEL org.opencontainers.image.title=${KEYCLOAK_SERVER_DISPLAY_NAME} \
      org.opencontainers.image.url=${KEYCLOAK_URL} \
      org.opencontainers.image.source=${KEYCLOAK_SOURCE} \
      org.opencontainers.image.description=${KEYCLOAK_SERVER_DESCRIPTION} \
      org.opencontainers.image.documentation=${KEYCLOAK_DOCS} \
      org.opencontainers.image.created=${BUILD_DATE} \
      org.opencontainers.image.revision=${VCS_REF} \
      org.opencontainers.image.version=${KEYCLOAK_VERSION} \
      org.opencontainers.image.vendor=${KEYCLOAK_VENDOR} \
      org.opencontainers.image.licenses="Apache-2.0"
