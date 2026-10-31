# Lab 6: competitor CLIs in one sandbox, off the host.
#   modernize  = Microsoft GitHub Copilot app modernization CLI (needs gh auth + a Copilot plan)
#   atx        = AWS Transform custom CLI (needs AWS credentials; billed per agent-minute)
# JDK 8 for the "before" petclinic, 17/21 for the "after"; Node 22 is required by atx.
FROM eclipse-temurin:8-jdk  AS jdk8
FROM eclipse-temurin:17-jdk AS jdk17
FROM node:22-bookworm
COPY --from=jdk8  /opt/java/openjdk /usr/lib/jvm/temurin-8
COPY --from=jdk17 /opt/java/openjdk /usr/lib/jvm/temurin-17
COPY --from=eclipse-temurin:21-jdk /opt/java/openjdk /usr/lib/jvm/temurin-21
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh maven unzip less jq \
 && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/temurin-21 PATH="/usr/lib/jvm/temurin-21/bin:/home/node/.local/bin:${PATH}"
# uid 1000 is the image's `node` user; we run as 1001 (mclose) at runtime, so give it a real home.
RUN useradd -m -u 1001 -s /bin/bash lab
USER lab
WORKDIR /home/lab
ENV PATH="/home/lab/.local/bin:/home/lab/bin:${PATH}"
RUN curl -fsSL https://raw.githubusercontent.com/microsoft/modernize-cli/main/scripts/install.sh | sh
RUN curl -fsSL https://transform-cli.awsstatic.com/install.sh | bash
