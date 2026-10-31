# shopNow: End-to-End DevOps Pipeline on AWS EKS

Jenkins, Docker, Terraform, Ansible, Kubernetes (AWS EKS), Prometheus and Grafana, applied to the **shopNow** MERN
shop (customer app, admin dashboard, Node.js API, MongoDB).

> This README covers **only what the assignment asks for**. ArgoCD, GitOps and per-app Helm charts are not part of it,
> so the old README sections about them were removed (see `git log` for the original). Helm is used only as an
> installer for ingress-nginx and the Prometheus/Grafana stack.

## 1. What you get

| Assignment requirement | Where |
|---|---|
| Architecture with load balancing, orchestration, monitoring | Section 2 |
| Terraform: VPC, subnets, security groups, EKS, EC2, state in S3 | `terraform/` |
| Ansible: configure EC2 (Docker, kubectl, AWS CLI, helm, node_exporter) | `ansible/` |
| Dockerized app, images in ECR | `backend/`, `frontend/`, `admin/` Dockerfiles, 3 ECR repos from Terraform |
| Kubernetes deployment with health checks and autoscaling | `kubernetes/k8s-manifests/` (probes, HPA, PDB) |
| Jenkins pipelines (Terraform, then Ansible, then build/deploy, then monitoring) | `jenkins/` |
| Prometheus + Grafana + alert rules + Jenkins alerts | `monitoring/` |
| Tests | `backend/tests/`, `scripts/smoke-test.sh`, `scripts/infra-tests.sh`, `ansible/playbooks/verify.yml` |
| Cost optimisation | Section 7 |

## 2. Architecture

```
 git push -> GitHub -> Jenkins (Hero Vired) -> infra-terraform -> config-ansible -> app-cicd -> monitoring-setup

 Internet -> AWS Network Load Balancer -> ingress-nginx -+- /<prefix>        -> frontend (nginx) -+
                                                         +- /<prefix>-admin  -> admin (nginx)    -+-> backend-service:5000 -> MongoDB (StatefulSet + EBS)

 AWS: VPC (2 AZs, public + private subnets, NAT) | EKS managed node group (3 x t3.medium spot, private subnets)
      3 ECR repos | EC2 tools host (Ansible) | S3 + DynamoDB (Terraform state)
 Monitoring: Prometheus scrapes backend /metrics, ingress-nginx, nodes, Jenkins -> Alertmanager -> Jenkins webhook | Grafana dashboards
```

## 3. Two ways to run it

| | **A. `run.sh`** (one command, runs on your machine) | **B. Jenkins** (what the assignment asks for) |
|---|---|---|
| Use it for | Getting everything up quickly, testing, debugging | The final demo: Jenkins orchestrates every stage |
| Steps | `./run.sh all` | Create 5 jobs (Section 5) and run `full-pipeline` |

Both run the same Terraform, Ansible, manifests and scripts and share the same Terraform state, so you can test with A
and demo with B. Do not run both against the same environment at the same time.

## 4. Prerequisites

1. **AWS account** with permission to create EC2, VPC, EKS, ECR, IAM, S3 and DynamoDB resources. Region defaults to `ap-south-1` (Mumbai).
2. **An EC2 key pair** in that region (EC2 console, Key Pairs, Create) and its `.pem` file.
3. **Linux or macOS shell** (on Windows use WSL2 with Ubuntu). Required tools: `aws` (v2), `terraform` (1.5+), `kubectl`, `helm`, `docker` (running), `ansible`, `python3` with `pyyaml`, `ssh`, `curl`.
   On Ubuntu 22.04 one command installs all of them: `sudo ./jenkins/install-jenkins-ec2.sh --tools-only` (it includes `pyyaml`; log out and back in so the docker group applies).
   Install guides for Docker, kubectl, helm and the AWS CLI are in `docs/TOOLS-SETUP-GUIDE.md`.
4. **AWS credentials** on your machine: `aws configure`. Verify with `aws sts get-caller-identity`.
5. **Your own fork** of this repository on GitHub (Jenkins jobs point at it).

Expect about **$0.31 per hour (about $7-8 per day)** while everything is running. See Section 7.

## 5A. Run with `run.sh`

```bash
cp config.env.example config.env
nano config.env                       # set SSH_KEY_NAME, SSH_KEY_FILE and the three passwords (letters and digits only)

./run.sh check                        # verifies tools, AWS login, key pair and config. Changes nothing.
./run.sh all                          # about 35-45 minutes: backend, infra, configure, app, monitoring, test, status
```

Or run the stages one at a time (each is safe to re-run):

| Command | What it does | Time |
|---|---|---|
| `./run.sh backend` | S3 bucket + DynamoDB table for Terraform state (once) | 1 min |
| `./run.sh infra` | Terraform: VPC, EKS, ECR, EC2 tools host | 15-20 min |
| `./run.sh configure` | Ansible configures the EC2 tools host and verifies it | 3 min |
| `./run.sh app` | Backend tests, build 3 images, push to ECR, deploy to EKS, smoke test | 10 min |
| `./run.sh monitoring` | Prometheus, Grafana, Alertmanager, alert rules, dashboard | 5 min |
| `./run.sh test` | Smoke tests plus infrastructure checks | 2 min |
| `./run.sh status` | Prints the app URLs and pod status | instant |
| `./run.sh destroy` | **Deletes everything that costs money** | 15 min |

When it finishes, `./run.sh status` prints:
- Customer app: `http://<load-balancer>/shopnow`
- Admin dashboard: `http://<load-balancer>/shopnow-admin`

The load balancer DNS name can take 2-3 minutes to start resolving. `/shopnow` is your `APP_PATH_PREFIX`.

## 5B. Run with Jenkins (Hero Vired server)

**1. Credentials** (Manage Jenkins, Credentials, Global, Add):

| ID | Kind | Value |
|---|---|---|
| `aws-credentials` | AWS Credentials | your access key and secret |
| `ec2-ssh-key` | SSH Username with private key | username `ubuntu`, contents of your `.pem` |
| `shopnow-mongo-app-password` | Secret text | letters and digits only |
| `shopnow-mongo-root-password` | Secret text | letters and digits only |

**2. Tools on the Jenkins agent:** `docker aws kubectl helm terraform ansible python3` with `pyyaml`. If you cannot install them on the shared server, ask your instructor or run the jobs on your own EC2 agent (`sudo jenkins/install-jenkins-ec2.sh` installs Jenkins plus the tools). Also install the plugins in `jenkins/plugins.txt`.

**3. State bucket** (once, from any machine with AWS access): `./run.sh backend`. It prints the bucket name (`shopnow-tfstate-<account-id>`).

**4. Create five Pipeline jobs** (New Item, Pipeline, *Pipeline script from SCM*, Git, your fork, branch `main`):

| Job name (exact) | Script Path | Fill in |
|---|---|---|
| `infra-terraform` | `jenkins/Jenkinsfile.terraform` | `TF_STATE_BUCKET`, `SSH_KEY_NAME`, `ADMIN_CIDR` (your IP/32 **and** the Jenkins server IP; keep `ACTION=plan` first, then `apply`) |
| `config-ansible` | `jenkins/Jenkinsfile.ansible` | Nothing: triggered automatically after `infra-terraform` applies |
| `app-cicd` | `jenkins/Jenkinsfile.app-cicd` | Defaults work (`EKS_CLUSTER_NAME=shopnow-dev-eks`, `APP_PATH_PREFIX=shopnow`). Polls Git every 5 minutes |
| `monitoring-setup` | `jenkins/Jenkinsfile.monitoring` | `GRAFANA_ADMIN_PASSWORD`, optionally `JENKINS_HOST` |
| `full-pipeline` | `jenkins/Jenkinsfile.full-pipeline` | `TF_STATE_BUCKET`, `SSH_KEY_NAME`, `ADMIN_CIDR`, `GRAFANA_ADMIN_PASSWORD` |

**5. Run `full-pipeline`.** It runs Terraform, then Ansible, then builds and deploys shopNow, then installs monitoring.
Later code pushes trigger only `app-cicd` (build, test, push, deploy, smoke test, automatic rollback on failure).

**6. Optional but recommended:** add a GitHub webhook to `https://<jenkins-host>/github-webhook/` for instant builds, and
uncomment the `mail` or `slackSend` line in `Jenkinsfile.app-cicd` to get failure notifications.

If Jenkins runs `kubectl` as a different AWS identity than the one that ran Terraform, give it cluster access:
```bash
aws eks create-access-entry --cluster-name shopnow-dev-eks --principal-arn <arn>
aws eks associate-access-policy --cluster-name shopnow-dev-eks --principal-arn <arn> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster
```
More detail on each job, the code changes and troubleshooting is in [PIPELINE.md](PIPELINE.md).

## 6. Verify it works (and what to show in the viva)

```bash
kubectl -n shopnow-demo get pods,svc,hpa,ing        # all Running, 2+ replicas of backend/frontend
kubectl -n shopnow-demo get sts mongo               # 1/1
kubectl top nodes                                   # metrics-server works, so autoscaling works
```
1. **Application:** open `/shopnow`, browse products, place an order. Open `/shopnow-admin` and see the order, mark it collected.
2. **Grafana:** `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80`, open http://localhost:3000, log in as `admin`, open the dashboard *shopNow - Application Overview*.
3. **Alerting:** `kubectl -n shopnow-demo scale deploy/backend --replicas=0`. After about 5 minutes the `BackendNoTargets` alert fires (Prometheus: `kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090`, then open `/alerts`). Restore with `--replicas=2`.
4. **Autoscaling:** `kubectl -n shopnow-demo get hpa`.
5. **Rollback:** the `app-cicd` job runs `kubectl rollout undo` if a deploy fails.
6. **Tests:** `./run.sh test`, or the Jenkins console output.

## 7. Cost and teardown

About **$0.31 per hour** while running (EKS control plane $0.10, nodes, NAT gateway, load balancer, volumes).
Spot nodes, a single NAT gateway, small instances, an ECR lifecycle policy (last 10 images) and Grafana as `ClusterIP` keep it low.

**Always tear down when you finish:**
```bash
./run.sh destroy                      # type: yes
```
Then check the AWS console (your region) for leftover EKS clusters, NAT gateways, load balancers and EC2 instances.
Set a budget alert first: AWS Budgets, monthly cost budget, email alert at a low amount.

Keep `cluster_version` in `terraform/variables.tf` on a version in **standard** support (default 1.35 until 27 March 2027).
Extended support costs $0.60 per hour for the control plane instead of $0.10.

## 8. Repository layout

```
run.sh, config.env.example   one-command execution (Section 5A)
backend/ frontend/ admin/    the shopNow app and its Dockerfiles
terraform/                   VPC, EKS (+ EBS CSI, metrics-server), ECR, EC2, S3 state config
ansible/                     roles + playbooks (site.yml, verify.yml)
kubernetes/k8s-manifests/    templated manifests (rendered by scripts/render-manifests.sh)
kubernetes/pre-req/          gp3 storage class
monitoring/                  Helm values, alert rules, ServiceMonitors, Grafana dashboard
jenkins/                     Jenkinsfiles, plugin list, tool installer
scripts/                     backend bootstrap, render, secrets, add-ons, smoke/infra tests, teardown
docs/                        original learning docs
```

Changes made to the original shopNow code: backend `/metrics`, unit tests and graceful shutdown; backend Docker health check
now uses `/api/health`; admin nginx now proxies `/api/` to the backend. The `aryan` placeholder is replaced by `APP_PATH_PREFIX`
(the image build argument and the ingress both read it), so there is nothing to edit by hand.

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| `./run.sh check` says a tool is missing | Install it (Section 4). Docker must be running |
| `AWS credentials not working` | `aws configure`, then `aws sts get-caller-identity` |
| `key pair ... does not exist` | Create it in the EC2 console in the same region as `AWS_REGION` |
| Cannot reach the cluster / `kubectl` times out | Your public IP changed: set `ADMIN_CIDR=<new-ip>/32` and run `./run.sh infra` again |
| SSH to the tools host times out (Ansible) | Same cause: `ADMIN_CIDR` does not contain your current IP |
| Backend `CrashLoopBackOff`, "MongoDB connection error" | Wait for `mongo-0` Ready: `kubectl -n shopnow-demo get pods`; then `kubectl -n shopnow-demo rollout restart deploy/backend` |
| `PVC Pending` | EBS CSI add-on not ACTIVE yet: `aws eks describe-addon --cluster-name shopnow-dev-eks --addon-name aws-ebs-csi-driver` |
| HPA shows `<unknown>` | metrics-server add-on not ACTIVE yet (wait a few minutes) |
| Blank page or 404 on assets | `APP_PATH_PREFIX` differs between the image build and the ingress. Run `./run.sh app` again with one value |
| Page not loading right after deploy | The load balancer DNS needs 2-3 minutes. Check `./run.sh status` |
| Changed a Mongo password but the app cannot log in | The user is created only on an empty volume: `kubectl -n shopnow-demo delete sts mongo` then `kubectl -n shopnow-demo delete pvc mongo-data-mongo-0`, then `./run.sh app` |
| `ECR RepositoryNotFound` | `ECR_NAMESPACE` must equal Terraform `ecr_namespace` (default `shopnow`) |
| Jenkins `Unauthorized` from kubectl | Add an EKS access entry (Section 5B) and add the Jenkins IP to `ADMIN_CIDR` |
| `terraform destroy` hangs on the VPC | Load balancers or volumes created by Kubernetes are still there: use `./run.sh destroy`, which removes them first |
| `Error acquiring the state lock` | A previous run crashed: `terraform -chdir=terraform force-unlock <ID>` |

## 10. Known limitations

- The shopNow backend has no authentication (a learning project): the admin and API endpoints are open to anyone who can reach the load balancer.
- One MongoDB replica with a 5Gi volume, plain HTTP, and one NAT gateway. Fine for the assignment, not for production.
- `ADMIN_CIDR` takes a single CIDR. Pass your IP, or the Jenkins server IP when running from Jenkins.
- The Terraform, Ansible and Jenkinsfile code was checked statically (syntax, rendering, references) and with stubbed tools, but not run against a real AWS account in the environment that produced it. Run `./run.sh check` and `terraform plan` first, and expect to fix small issues on the first real run.
