# Build Keycloak from the local source checkout, then package it in a
# hardened UBI micro runtime image.

FROM maven:3.9.15-eclipse-temurin-8 AS source-build

WORKDIR /workspace

COPY . .

# Default Maven flags focus on a fast, reproducible source build inside CI/CD.
ARG KEYCLOAK_BUILD_CMD="clean install"
ARG MAVEN_CLI_OPTS="-B -ntp -DskipTests -DskipTestsuite -DskipExamples -DskipProtoLock=true"

RUN chmod +x mvnw \
	&& if [ -f maven-settings.xml ]; then \
		./mvnw -s maven-settings.xml -pl quarkus/deployment,quarkus/dist -am ${KEYCLOAK_BUILD_CMD} ${MAVEN_CLI_OPTS}; \
	else \
		./mvnw -pl quarkus/deployment,quarkus/dist -am ${KEYCLOAK_BUILD_CMD} ${MAVEN_CLI_OPTS}; \
	fi \
	&& mkdir -p /tmp/keycloak \
	&& artifact="$(ls -1 quarkus/dist/target/keycloak-*.tar.gz | head -n 1)" \
	&& cp "$artifact" /tmp/keycloak/keycloak.tar.gz


FROM registry.access.redhat.com/ubi9 AS ubi-micro-build

RUN dnf install -y tar gzip \
	&& dnf clean all \
	&& rm -rf /var/cache/dnf

COPY --from=source-build /tmp/keycloak/keycloak.tar.gz /tmp/keycloak/keycloak.tar.gz

RUN mkdir -p /tmp/keycloak \
	&& tar -xvf /tmp/keycloak/keycloak.tar.gz -C /tmp/keycloak \
	&& rm /tmp/keycloak/keycloak.tar.gz \
	&& mv /tmp/keycloak/keycloak-* /opt/keycloak \
	&& mkdir -p /opt/keycloak/data \
	&& chmod -R g+rwX /opt/keycloak

COPY quarkus/container/ubi-null.sh /tmp/ubi-null.sh
RUN bash /tmp/ubi-null.sh java-21-openjdk-headless glibc-langpack-en findutils


FROM registry.access.redhat.com/ubi9-micro

ARG KEYCLOAK_SOURCE="https://github.com/keycloak/keycloak"
ARG BUILD_DATE
ARG VCS_REF

ENV LANG=en_US.UTF-8 \
	KC_RUN_IN_CONTAINER=true

COPY --from=ubi-micro-build /tmp/null/rootfs/ /
COPY --from=ubi-micro-build --chown=1000:0 /opt/keycloak /opt/keycloak

RUN echo "keycloak:x:0:root" >> /etc/group \
	&& echo "keycloak:x:1000:0:keycloak user:/opt/keycloak:/sbin/nologin" >> /etc/passwd

LABEL org.opencontainers.image.title="Keycloak" \
	  org.opencontainers.image.description="Keycloak built from local source" \
	  org.opencontainers.image.url="https://www.keycloak.org/" \
	  org.opencontainers.image.source="${KEYCLOAK_SOURCE}" \
	  org.opencontainers.image.created="${BUILD_DATE}" \
	  org.opencontainers.image.revision="${VCS_REF}"

USER 1000

EXPOSE 8080 8443 9000

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start"]
