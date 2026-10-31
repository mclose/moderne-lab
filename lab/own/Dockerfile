# moderne-lab-own: the Lab 2 CLI image plus Python (the CLI's Python parser needs 3.12+).
FROM moderne-lab-cli
USER root
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*
USER lab
