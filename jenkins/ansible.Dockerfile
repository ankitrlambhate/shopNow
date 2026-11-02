FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir ansible boto3 botocore

COPY ansible/requirements.yml /tmp/ansible-requirements.yml
RUN ansible-galaxy collection install \
    --collections-path /usr/share/ansible/collections \
    -r /tmp/ansible-requirements.yml

WORKDIR /workspace
