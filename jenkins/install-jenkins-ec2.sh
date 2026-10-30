#!/usr/bin/env bash
# OPTIONAL: installs Jenkins + all build tools on a fresh Ubuntu 22.04 EC2 instance.
# You said you will use the Hero Vired Jenkins server, so you normally do NOT need this for Jenkins itself.
# However, the Jenkins agent that runs the pipelines needs the same tools (docker, aws, kubectl, helm,
# terraform, ansible, envsubst). Run with --tools-only on the Hero Vired agent/host if you have shell access.
#
# Usage:
#   sudo ./install-jenkins-ec2.sh              # Jenkins + tools
#   sudo ./install-jenkins-ec2.sh --tools-only # tools only
set -euo pipefail

TOOLS_ONLY=false
[ "${1:-}" = "--tools-only" ] && TOOLS_ONLY=true

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg unzip jq git gettext-base python3 python3-venv python3-pip software-properties-common

# ---------- Docker ----------
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
  systemctl enable --now docker
fi

# ---------- AWS CLI v2 ----------
if ! command -v aws >/dev/null; then
  curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
fi

# ---------- kubectl ----------
if ! command -v kubectl >/dev/null; then
  KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSL "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
  chmod +x /usr/local/bin/kubectl
fi

# ---------- helm ----------
if ! command -v helm >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# ---------- Terraform ----------
if ! command -v terraform >/dev/null; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo $VERSION_CODENAME) main" > /etc/apt/sources.list.d/hashicorp.list
  apt-get update -y
  apt-get install -y terraform
fi

# ---------- Ansible ----------
if ! command -v ansible >/dev/null; then
  pip3 install --break-system-packages ansible boto3 botocore pyyaml 2>/dev/null || pip3 install ansible boto3 botocore pyyaml
fi

if [ "$TOOLS_ONLY" = true ]; then
  # give the jenkins user (if it exists) access to docker
  id jenkins >/dev/null 2>&1 && usermod -aG docker jenkins || true
  echo "Tools installed."
  exit 0
fi

# ---------- Jenkins ----------
apt-get install -y fontconfig openjdk-17-jre
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key -o /usr/share/keyrings/jenkins-keyring.asc
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
apt-get update -y
apt-get install -y jenkins
usermod -aG docker jenkins
systemctl enable --now jenkins

# ---------- Plugins ----------
PLUGINS_FILE="$(dirname "$0")/plugins.txt"
if [ -f "$PLUGINS_FILE" ]; then
  curl -fsSL https://github.com/jenkinsci/plugin-installation-manager-tool/releases/latest/download/jenkins-plugin-manager.jar -o /tmp/jpm.jar || true
  if [ -f /tmp/jpm.jar ]; then
    java -jar /tmp/jpm.jar --war /usr/share/java/jenkins.war \
      --plugin-file "$PLUGINS_FILE" --plugin-download-directory /var/lib/jenkins/plugins || true
    chown -R jenkins:jenkins /var/lib/jenkins/plugins
    systemctl restart jenkins
  fi
fi

echo "Jenkins is starting on port 8080."
echo "Initial admin password:"
cat /var/lib/jenkins/secrets/initialAdminPassword || true
