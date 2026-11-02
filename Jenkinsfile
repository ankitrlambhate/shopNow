pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    skipDefaultCheckout(true)
    timeout(time: 150, unit: 'MINUTES')
  }

  triggers {
    pollSCM('H/5 * * * *')
  }

  parameters {
    choice(name: 'WORKFLOW', choices: ['app-cicd', 'full', 'terraform', 'ansible', 'monitoring'], description: 'Run the application pipeline (default), the full stack, or one component')
    choice(name: 'TERRAFORM_ACTION', choices: ['plan', 'apply', 'destroy'], description: 'Terraform action (full workflow requires apply)')
    string(name: 'AWS_REGION', defaultValue: 'ap-south-1', description: 'AWS region')
    string(name: 'ENVIRONMENT', defaultValue: 'dev', description: 'Environment (dev/staging/prod)')
    string(name: 'TF_STATE_BUCKET', defaultValue: '', description: 'Terraform state bucket from scripts/bootstrap-tf-backend.sh')
    string(name: 'TF_LOCK_TABLE', defaultValue: 'shopnow-tf-lock', description: 'DynamoDB lock table')
    string(name: 'SSH_KEY_NAME', defaultValue: '', description: 'Existing EC2 key pair name')
    string(name: 'ADMIN_CIDR', defaultValue: '0.0.0.0/0', description: 'CIDR allowed to SSH / reach the EKS API (tighten this)')
    string(name: 'AWS_CREDENTIALS_ID', defaultValue: 'ankitlambhate-aws-credentials', description: 'Jenkins AWS credentials ID')
    booleanParam(name: 'USE_INSTANCE_ROLE', defaultValue: false, description: 'Use the agent IAM role instead of Jenkins AWS credentials')
    booleanParam(name: 'AUTO_APPROVE', defaultValue: false, description: 'Skip Terraform apply/destroy approval')
    booleanParam(name: 'RUN_ANSIBLE', defaultValue: true, description: 'Run Ansible after a standalone Terraform apply')
    string(name: 'SSH_CREDENTIALS_ID', defaultValue: 'ankit-ec2-ssh-key', description: 'Jenkins SSH private-key credential ID')
    booleanParam(name: 'CHECK_MODE', defaultValue: false, description: 'Run Ansible in dry-run mode')
    string(name: 'EKS_CLUSTER_NAME', defaultValue: 'shopnow-dev-eks', description: 'EKS cluster name for standalone app, Ansible, or monitoring workflows')
    string(name: 'ECR_NAMESPACE', defaultValue: 'shopnow', description: 'ECR repository prefix')
    string(name: 'APP_PATH_PREFIX', defaultValue: 'shopnow', description: 'Application URL prefix')
    string(name: 'NAMESPACE', defaultValue: 'shopnow-demo', description: 'Kubernetes application namespace')
    booleanParam(name: 'DEPLOY', defaultValue: true, description: 'Deploy the application after pushing images')
    booleanParam(name: 'RUN_WRITE_TESTS', defaultValue: true, description: 'Smoke test creates and cancels a test order')
    string(name: 'MONGO_APP_PW_ID', defaultValue: 'shopnow-mongo-app-password', description: 'Jenkins secret-text ID for the MongoDB app user')
    string(name: 'MONGO_ROOT_PW_ID', defaultValue: 'shopnow-mongo-root-password', description: 'Jenkins secret-text ID for the MongoDB root user')
    string(name: 'JENKINS_HOST', defaultValue: '', description: 'Jenkins hostname without https:// (optional monitoring target)')
    string(name: 'BASTION_PRIVATE_IP', defaultValue: '', description: 'Tools-host private IP for node_exporter monitoring (optional)')
    choice(name: 'GRAFANA_SERVICE_TYPE', choices: ['LoadBalancer', 'ClusterIP'], description: 'Grafana exposure type')
    password(name: 'GRAFANA_ADMIN_PASSWORD', defaultValue: '', description: 'Grafana admin password (required for monitoring)')
  }

  environment {
    TF_IN_AUTOMATION = 'true'
    TF_INPUT = '0'
    TF_DIR = 'terraform'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.GIT_SHORT = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_SHORT}"
          env.ANSIBLE_IMAGE = "shopnow-ansible:${env.BUILD_NUMBER}"
          env.EKS_CLUSTER_NAME = params.WORKFLOW == 'full' ? "shopnow-${params.ENVIRONMENT}-eks" : params.EKS_CLUSTER_NAME
          echo "Image tag: ${env.IMAGE_TAG}"
        }
      }
    }

    stage('Validate Inputs') {
      steps {
        script {
          if (['full', 'terraform'].contains(params.WORKFLOW)) {
            if (!params.TF_STATE_BUCKET?.trim()) error 'TF_STATE_BUCKET is required for Terraform'
            if (!params.SSH_KEY_NAME?.trim()) error 'SSH_KEY_NAME is required for Terraform'
          }
          if (params.WORKFLOW == 'full' && params.TERRAFORM_ACTION != 'apply') {
            error 'The full workflow requires TERRAFORM_ACTION=apply'
          }
          if (['full', 'monitoring'].contains(params.WORKFLOW)) {
            sh 'set +x; test -n "$GRAFANA_ADMIN_PASSWORD" || { echo "GRAFANA_ADMIN_PASSWORD is required for monitoring" >&2; exit 1; }'
          }
        }
      }
    }

    stage('Terraform Init & Validate') {
      when { expression { runsTerraform() } }
      steps {
        withAws {
          dir(env.TF_DIR) {
            sh '''
              terraform fmt -check -recursive
              terraform init -reconfigure \
                -backend-config="bucket=${TF_STATE_BUCKET}" \
                -backend-config="dynamodb_table=${TF_LOCK_TABLE}" \
                -backend-config="region=${AWS_REGION}" \
                -backend-config="key=shopnow/${ENVIRONMENT}/terraform.tfstate"
              terraform validate
            '''
          }
        }
      }
    }

    stage('Terraform Plan') {
      when { expression { runsTerraform() } }
      steps {
        withAws {
          dir(env.TF_DIR) {
            sh '''
                TF_DESTROY_FLAG=""
                if [ "$TERRAFORM_ACTION" = "destroy" ]; then TF_DESTROY_FLAG="-destroy"; fi
                terraform plan $TF_DESTROY_FLAG -out=tfplan \
                  -var="aws_region=${AWS_REGION}" \
                  -var="environment=${ENVIRONMENT}" \
                  -var="ssh_key_name=${SSH_KEY_NAME}" \
                  -var="admin_cidr=${ADMIN_CIDR}"
                terraform show -no-color tfplan > tfplan.txt
            '''
          }
        }
        archiveArtifacts artifacts: 'terraform/tfplan.txt'
      }
    }

    stage('Terraform Approval') {
      when {
        allOf {
          expression { runsTerraform() && params.TERRAFORM_ACTION != 'plan' }
          expression { !params.AUTO_APPROVE }
        }
      }
      steps {
        timeout(time: 30, unit: 'MINUTES') {
          input message: "Review tfplan.txt (archived). Proceed with terraform ${params.TERRAFORM_ACTION} on ${params.ENVIRONMENT}?", ok: 'Proceed'
        }
      }
    }

    stage('Terraform Apply / Destroy') {
      when { expression { runsTerraform() && params.TERRAFORM_ACTION != 'plan' } }
      steps {
        withAws {
          dir(env.TF_DIR) {
            sh 'terraform apply -auto-approve tfplan'
          }
        }
      }
    }

    stage('Export Terraform Outputs') {
      when { expression { runsTerraform() && params.TERRAFORM_ACTION == 'apply' } }
      steps {
        withAws {
          dir(env.TF_DIR) {
            sh 'terraform output -json > ../tf-outputs.json'
          }
        }
        archiveArtifacts artifacts: 'tf-outputs.json'
        script {
          def out = readJSON(file: 'tf-outputs.json')
          env.EKS_CLUSTER_NAME = out.cluster_name.value
          env.BASTION_PRIVATE_IP = out.bastion_private_ip.value
          echo "Cluster: ${env.EKS_CLUSTER_NAME} | Tools host: ${env.BASTION_PRIVATE_IP}"
        }
      }
    }

    stage('Install Ansible Tooling') {
      when { expression { runsAnsible() } }
      steps {
        sh 'docker build --pull -f jenkins/ansible.Dockerfile -t "$ANSIBLE_IMAGE" .'
      }
    }

    stage('Ansible Syntax Check') {
      when { expression { runsAnsible() } }
      steps {
        sh '''
          docker run --rm --network host --user "$(id -u):$(id -g)" \
            -e HOME=/tmp -e ANSIBLE_CONFIG=/workspace/ansible/ansible.cfg \
            -v "$WORKSPACE:/workspace" -w /workspace/ansible \
            "$ANSIBLE_IMAGE" \
            ansible-playbook playbooks/site.yml --syntax-check -i inventory/hosts.ini.example
        '''
      }
    }

    stage('Configure Tools Host') {
      when { expression { runsAnsible() } }
      steps {
        script {
          if (params.WORKFLOW == 'full' || (params.WORKFLOW == 'terraform' && params.TERRAFORM_ACTION == 'apply')) {
            sleep time: 60, unit: 'SECONDS'
          }
        }
        withCredentials([sshUserPrivateKey(credentialsId: params.SSH_CREDENTIALS_ID, keyFileVariable: 'SSH_KEY_FILE', usernameVariable: 'SSH_USER')]) {
          withAws {
            sh '''
              docker run --rm --network host --user "$(id -u):$(id -g)" \
                -e HOME=/tmp -e ANSIBLE_CONFIG=/workspace/ansible/ansible.cfg \
                -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_ACCESS_KEY_ID \
                -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
                -e EKS_CLUSTER_NAME -e CHECK_MODE -e SSH_USER \
                -v "$WORKSPACE:/workspace" \
                -v "$SSH_KEY_FILE:/tmp/jenkins-ssh-key:ro" \
                -w /workspace/ansible "$ANSIBLE_IMAGE" \
                sh -ec '
                  sed -i "s/ap-south-1/$AWS_REGION/" inventory/aws_ec2.yml
                  CHECK=""
                  if [ "$CHECK_MODE" = "true" ]; then CHECK="--check"; fi
                  ansible-playbook playbooks/site.yml $CHECK \
                    --private-key /tmp/jenkins-ssh-key -u "$SSH_USER"
                '
            '''
          }
        }
      }
    }

    stage('Verify Tools Host') {
      when { expression { runsAnsible() && !params.CHECK_MODE } }
      steps {
        withCredentials([sshUserPrivateKey(credentialsId: params.SSH_CREDENTIALS_ID, keyFileVariable: 'SSH_KEY_FILE', usernameVariable: 'SSH_USER')]) {
          withAws {
            sh '''
              docker run --rm --network host --user "$(id -u):$(id -g)" \
                -e HOME=/tmp -e ANSIBLE_CONFIG=/workspace/ansible/ansible.cfg \
                -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_ACCESS_KEY_ID \
                -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e SSH_USER \
                -v "$WORKSPACE:/workspace" \
                -v "$SSH_KEY_FILE:/tmp/jenkins-ssh-key:ro" \
                -w /workspace/ansible "$ANSIBLE_IMAGE" \
                ansible-playbook playbooks/verify.yml \
                  --private-key /tmp/jenkins-ssh-key -u "$SSH_USER"
            '''
          }
        }
      }
    }

    stage('Backend Unit Tests') {
      when { expression { runsApp() } }
      steps {
        sh '''
          docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e npm_config_cache=/tmp/.npm \
            -v "$WORKSPACE/backend":/app -w /app node:20-alpine \
            sh -c "npm ci --no-audit --no-fund && npm test"
        '''
      }
    }

    stage('Resolve ECR Registry') {
      when { expression { runsApp() } }
      steps {
        script {
          withAws {
            env.ACCOUNT_ID = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
            env.ECR_REGISTRY = "${env.ACCOUNT_ID}.dkr.ecr.${params.AWS_REGION}.amazonaws.com"
          }
          echo "Registry: ${env.ECR_REGISTRY}"
        }
      }
    }

    stage('Build Images') {
      when { expression { runsApp() } }
      parallel {
        stage('Build backend') {
          steps {
            sh 'docker build -t $ECR_REGISTRY/$ECR_NAMESPACE/backend:$IMAGE_TAG backend'
          }
        }
        stage('Build frontend') {
          steps {
            sh 'docker build --build-arg USER_NAME=$APP_PATH_PREFIX -t $ECR_REGISTRY/$ECR_NAMESPACE/frontend:$IMAGE_TAG frontend'
          }
        }
        stage('Build admin') {
          steps {
            sh 'docker build --build-arg USER_NAME=$APP_PATH_PREFIX -t $ECR_REGISTRY/$ECR_NAMESPACE/admin:$IMAGE_TAG admin'
          }
        }
      }
    }

    stage('Image Scan (optional)') {
      when { expression { runsApp() } }
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          sh '''
            if command -v trivy >/dev/null 2>&1; then
              for svc in backend frontend admin; do
                trivy image --severity HIGH,CRITICAL --exit-code 0 --no-progress $ECR_REGISTRY/$ECR_NAMESPACE/$svc:$IMAGE_TAG
              done
            else
              echo "trivy not installed on this agent: skipping scan"
            fi
          '''
        }
      }
    }

    stage('Push to ECR') {
      when { expression { runsApp() } }
      steps {
        withAws {
          sh '''
            aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
            for svc in backend frontend admin; do
              docker push $ECR_REGISTRY/$ECR_NAMESPACE/$svc:$IMAGE_TAG
            done
          '''
          sh '''
            EP=$(aws eks describe-cluster --region ap-south-1 --name shopnow-dev-eks --query cluster.endpoint --output text)
            echo "endpoint: $EP"
            curl -sk -m 15 -o /dev/null -w "HTTP %{http_code} in %{time_total}s\\n" "$EP/version" || echo "CONNECT FAILED"
            curl -s https://checkip.amazonaws.com
          '''
        }
      }
    }

    stage('Install Cluster Add-ons') {
      when { expression { runsApp() && params.DEPLOY } }
      steps {
        withAws {
          sh '''
            aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME
            chmod +x scripts/*.sh
            ./scripts/install-cluster-addons.sh
          '''
        }
      }
    }

    stage('Render & Validate Manifests') {
      when { expression { runsApp() } }
      steps {
        sh '''
          chmod +x scripts/*.sh
          ./scripts/render-manifests.sh rendered
          python3 - <<'PY'
import glob, sys
try:
    import yaml
except ImportError:
    print("pyyaml not installed: skipping YAML syntax check"); sys.exit(0)
files = sorted(glob.glob("rendered/**/*.yaml", recursive=True))
for f in files:
    list(yaml.safe_load_all(open(f)))
print("Parsed %d manifests OK" % len(files))
PY
          if grep -rnE '[$][{](NAMESPACE|ECR_REGISTRY|ECR_NAMESPACE|IMAGE_TAG|APP_PATH_PREFIX)[}]' rendered/; then
            echo "Unrendered template variables found"; exit 1
          fi
        '''
      }
    }

    stage('Deploy to EKS') {
      when { expression { runsApp() && params.DEPLOY } }
      steps {
        script {
          env.DEPLOY_STARTED = 'true'
          withAws {
            withCredentials([
              string(credentialsId: params.MONGO_APP_PW_ID, variable: 'MONGO_APP_PASSWORD'),
              string(credentialsId: params.MONGO_ROOT_PW_ID, variable: 'MONGO_ROOT_PASSWORD')
            ]) {
              sh '''
                set -e
                aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME
                kubectl apply -f rendered/namespace/
                ./scripts/create-secrets.sh
                kubectl apply -f rendered/database/
                kubectl -n $NAMESPACE rollout status statefulset/mongo --timeout=420s
                kubectl apply -f rendered/backend/
                kubectl -n $NAMESPACE rollout status deployment/backend --timeout=300s
                kubectl apply -f rendered/frontend/ -f rendered/admin/
                kubectl -n $NAMESPACE rollout status deployment/frontend --timeout=300s
                kubectl -n $NAMESPACE rollout status deployment/admin --timeout=300s
                kubectl apply -f rendered/ingress/
                kubectl -n $NAMESPACE get deploy,sts,svc,hpa,ing
              '''
            }
          }
        }
      }
    }

    stage('Smoke Test') {
      when { expression { runsApp() && params.DEPLOY } }
      steps {
        script {
          withAws {
            sh '''
              aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME
              WRITE_TESTS=${RUN_WRITE_TESTS} ./scripts/smoke-test.sh
            '''
          }
          env.APP_DEPLOY_SUCCEEDED = 'true'
        }
      }
    }

    stage('Prepare Monitoring') {
      when { expression { runsMonitoring() } }
      steps {
        sh '''
          chmod +x scripts/*.sh
          ./scripts/prepare-monitoring.sh
        '''
      }
    }

    stage('Install Monitoring Stack') {
      when { expression { runsMonitoring() } }
      steps {
        withAws {
          sh '''
            set +x
            aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME
            kubectl apply -f kubernetes/pre-req/storageclass-gp3.yaml
            helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
            helm repo update
            helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
              -n monitoring --create-namespace \
              -f monitoring/values.rendered.yaml \
              --set grafana.adminPassword="$GRAFANA_ADMIN_PASSWORD" \
              --set grafana.service.type="$GRAFANA_SERVICE_TYPE" \
              --wait --timeout 15m
            kubectl apply -f monitoring/alert-rules.rendered.yaml
            kubectl apply -f monitoring/servicemonitors.rendered.yaml
            kubectl apply -f monitoring/grafana-dashboard-shopnow.yaml
          '''
        }
      }
    }

    stage('Verify Monitoring') {
      when { expression { runsMonitoring() } }
      steps {
        withAws {
          sh '''
            kubectl -n monitoring rollout status deployment/kube-prometheus-stack-grafana --timeout=300s
            kubectl -n monitoring get pods
            kubectl -n monitoring get prometheusrule,servicemonitor
            echo "Grafana user: admin"
            if [ "$GRAFANA_SERVICE_TYPE" = "LoadBalancer" ]; then
              H=""
              for i in $(seq 1 30); do
                H=$(kubectl -n monitoring get svc kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
                [ -n "$H" ] && break
                sleep 10
              done
              if [ -z "$H" ]; then
                echo "Grafana load balancer hostname was not assigned in time" >&2
                exit 1
              fi
              echo "Grafana URL: http://$H"
            else
              echo "Grafana: kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80"
            fi
          '''
        }
      }
    }
  }

  post {
    success {
      echo "shopNow pipeline completed: workflow=${params.WORKFLOW}, image=${env.IMAGE_TAG}"
    }
    failure {
      script {
        if (env.DEPLOY_STARTED == 'true' && env.APP_DEPLOY_SUCCEEDED != 'true') {
          echo 'Deployment failed: attempting to roll back application deployments.'
          try {
            withAws {
              sh '''
                aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME || true
                for d in backend frontend admin; do
                  kubectl -n $NAMESPACE rollout undo deployment/$d || true
                done
              '''
            }
          } catch (err) {
            echo "Rollback skipped: ${err}"
          }
        }
      }
    }
    always {
      sh 'docker image rm "$ANSIBLE_IMAGE" || true; docker image prune -f || true'
      cleanWs(deleteDirs: true, notFailBuild: true)
    }
  }
}

def runsTerraform() {
  return ['full', 'terraform'].contains(params.WORKFLOW)
}

def runsAnsible() {
  return params.WORKFLOW == 'full' ||
    params.WORKFLOW == 'ansible' ||
    (params.WORKFLOW == 'terraform' && params.TERRAFORM_ACTION == 'apply' && params.RUN_ANSIBLE)
}

def runsApp() {
  return ['full', 'app-cicd'].contains(params.WORKFLOW)
}

def runsMonitoring() {
  return ['full', 'monitoring'].contains(params.WORKFLOW)
}

def awsEnv() {
  return ["AWS_REGION=${params.AWS_REGION}", "AWS_DEFAULT_REGION=${params.AWS_REGION}"]
}

def withAws(Closure body) {
  if (params.USE_INSTANCE_ROLE) {
    withEnv(awsEnv()) { body() }
  } else {
    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: params.AWS_CREDENTIALS_ID]]) {
      withEnv(awsEnv()) { body() }
    }
  }
}
