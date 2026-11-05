# Moderne CLI sandbox: keeps the CLI, its JDKs, and ~/.moderne off the host.
# Multiple JDKs because `mod build` compiles each repo with the Java it targets.
FROM eclipse-temurin:8-jdk  AS jdk8
FROM eclipse-temurin:11-jdk AS jdk11
FROM eclipse-temurin:17-jdk AS jdk17
FROM eclipse-temurin:21-jdk
COPY --from=jdk8  /opt/java/openjdk /usr/lib/jvm/temurin-8
COPY --from=jdk11 /opt/java/openjdk /usr/lib/jvm/temurin-11
COPY --from=jdk17 /opt/java/openjdk /usr/lib/jvm/temurin-17
RUN apt-get update && apt-get install -y --no-install-recommends git curl unzip less maven bsdextrautils && rm -rf /var/lib/apt/lists/*
# The scripts build with your uid/gid (LAB_UID/LAB_GID) so files in the bind-mounted /ws stay owned by you.
ARG LAB_UID=1000
ARG LAB_GID=1000
RUN groupadd -o -g "$LAB_GID" lab && useradd -m -o -u "$LAB_UID" -g lab lab
USER lab
WORKDIR /home/lab
# Installer skips the browser login when there is no TTY; log in with a token later if wanted.
RUN curl -fsSL https://app.moderne.io/cli | bash
ENV PATH="/home/lab/.moderne/cli/bin:${PATH}"
RUN mod --version && mod config java installation list
