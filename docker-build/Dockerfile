FROM eclipse-temurin:21-jdk-jammy

ARG MAVEN_VERSION=3.9.6

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        ca-certificates \
        locales \
    && locale-gen zh_TW.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
    "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
    | tar -xzC /opt \
    && ln -s /opt/apache-maven-${MAVEN_VERSION}/bin/mvn /usr/local/bin/mvn

ENV MAVEN_HOME=/opt/apache-maven-3.9.6
ENV LANG=zh_TW.UTF-8
ENV LC_ALL=zh_TW.UTF-8
ENV TZ=Asia/Taipei

COPY scripts/entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
