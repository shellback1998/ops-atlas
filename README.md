# Ops Atlas

Ops Atlas is a hands-on hybrid deployment lab. The same application source runs in a Docker container on a Turing Pi K3s cluster and on an AWS EC2 instance. The dashboard reads `/api/status` to show which environment served the page.

## Deployment map

| Component | Location | Role |
| --- | --- | --- |
| Source and ARM64 image builds | `turing-manager` | Edit the app, build ARM64 images, push to the local registry |
| Image registry | `turing-node01:5000` | Store images for the Turing Pi cluster |
| K3s administration | `k8s-manager` | Apply manifests and inspect the cluster |
| K3s application | Turing Pi ARM64 worker | Run the dashboard and status API |
| AWS administration | `devops-manager` | Run Terraform and Ansible, keep local Terraform state |
| AWS application | `ops-atlas-aws` EC2 host | Run the AMD64 Docker image |

The K3s and AWS images currently come from the same source but are built separately for ARM64 and AMD64. Publishing a single multi-platform image is a later lab step.

## Open and identify each deployment

Connect your device to the tailnet, then open:

| Environment | Dashboard | API | Deployed version at time of writing |
| --- | --- | --- | --- |
| Turing Pi K3s | <http://ops-atlas> | <http://ops-atlas/api/status> | `0.3` |
| AWS EC2 | <http://ops-atlas-aws:8080> | <http://ops-atlas-aws:8080/api/status> | `0.5` |

The API returns `target`, `version`, `hostname`, and `time_utc`. On page load, `status.js` highlights the matching card. Version `0.5` also displays a prominent runtime banner; the K3s deployment will gain that banner after its next image rollout. Refresh the page to fetch current status; it does not poll continuously. These tailnet hostnames are not public internet domains.

## Application files

| File | Purpose |
| --- | --- |
| `index.html` | Dashboard layout and styling |
| `status.js` | Fetch `/api/status` and display the active environment |
| `server.py` | Serve the dashboard and JSON status API on port 8080 |
| `Dockerfile` | Package the Python application |
| `k8s/ops-atlas.yaml` | Namespace, Deployment, and internal Service |
| `k8s/tailscale.yaml` | Tailscale LoadBalancer Service |
| `terraform/aws/main.tf` | Define the AWS EC2 instance |
| `ansible/inventory.ini` | Connect Ansible to the AWS host over Tailscale |
| `ansible/bootstrap-aws.yml` | Install Git and Docker on Amazon Linux 2023 |
| `ansible/build-aws.yml` | Copy application files and build an AMD64 image on EC2 |
| `ansible/run-aws.yml` | Start the AWS container if it does not exist |

## Work locally with Docker

On `turing-manager`, from the repository root:

```bash
docker build -t ops-atlas:local .
docker run --rm -d --name ops-atlas-local -p 8083:8080 \
  -e DEPLOYMENT_TARGET=local-docker -e APP_VERSION=local ops-atlas:local
curl http://localhost:8083/api/status
docker stop ops-atlas-local
```

If Docker reports that the name or port is already in use, inspect existing lab containers with `docker ps -a --filter name=ops-atlas` before starting another preview.

## Turing Pi K3s

Build and push an ARM64 image from `turing-manager`; match the tag in `k8s/ops-atlas.yaml` to the image you push. The local registry uses HTTP, so each K3s worker that pulls from it must already have containerd registry configuration for `192.168.8.191:5000`.

```bash
docker buildx build --platform linux/arm64 \
  -t 192.168.8.191:5000/ops-atlas:0.3-arm64 --load .
docker push 192.168.8.191:5000/ops-atlas:0.3-arm64
```

The current workflow copies the Kubernetes manifests to `k8s-manager` and applies them there:

```bash
scp k8s/ops-atlas.yaml k8s/tailscale.yaml piadmin@k8s-manager:/tmp/
```

On `k8s-manager`:

```bash
kubectl apply -f /tmp/ops-atlas.yaml -f /tmp/tailscale.yaml
kubectl rollout status deployment/ops-atlas -n ops-atlas --timeout=120s
kubectl get pods -n ops-atlas -o wide
kubectl get service ops-atlas-tailscale -n ops-atlas
curl http://ops-atlas/api/status
k3s-status
k3s-health
```

To deploy a newer version, update the image tag, `APP_VERSION`, and manifest files, then push the image before applying the updated manifests. Do not rely on a mutable tag to indicate a new version.

## AWS: Terraform and Ansible

Run these commands on `devops-manager`, from its `~/ops-atlas` checkout. AWS credentials and Tailscale SSH access must already be set up. The Terraform configuration uses an existing subnet, a security group without inbound rules, and an existing SSM instance profile. Terraform state is local to this checkout and must be retained until the instance is destroyed.

```bash
terraform -chdir=terraform/aws init
terraform -chdir=terraform/aws plan
terraform -chdir=terraform/aws apply
terraform -chdir=terraform/aws output
```

The EC2 host is Amazon Linux 2023 on AMD64. In this lab Tailscale was installed and enrolled manually as `ops-atlas-aws`; it is not provisioned by the Terraform or Ansible files. Once the host is enrolled, check noninteractive access and configure the app:

```bash
ssh -o BatchMode=yes ec2-user@ops-atlas-aws 'hostname && id -un'
ansible aws -i ansible/inventory.ini -m ping
ansible-playbook -i ansible/inventory.ini ansible/bootstrap-aws.yml
ansible-playbook -i ansible/inventory.ini ansible/build-aws.yml
ansible-playbook -i ansible/inventory.ini ansible/run-aws.yml
curl http://ops-atlas-aws:8080/api/status
```

`bootstrap-aws.yml` installs Git and Docker and enables Docker. `build-aws.yml` copies the app from `devops-manager` and builds it on EC2; it is not pulling the local registry image. `run-aws.yml` starts a container only when one with the expected name does not already exist. For an image update, change the version in both AWS playbooks, rebuild, remove the existing container, and rerun `run-aws.yml`:

```bash
ansible aws -i ansible/inventory.ini -b -m command -a 'docker rm -f ops-atlas-aws'
ansible-playbook -i ansible/inventory.ini ansible/run-aws.yml
```

The Docker port is reachable on the tailnet as `http://ops-atlas-aws:8080`; this lab does not open an AWS inbound security group rule for the app.

## Cleanup

An EC2 instance, its attached storage, and its public IPv4 address may incur charges while allocated. On `devops-manager`, after finishing the AWS lab:

```bash
terraform -chdir=terraform/aws plan -destroy
terraform -chdir=terraform/aws destroy
terraform -chdir=terraform/aws state list
```

Check that the instance is gone in AWS, then remove `ops-atlas-aws` from the Tailscale admin console. Destroying EC2 does not automatically remove its Tailscale device. Do not delete Terraform state before confirming destroy completed. Tailscale was enrolled manually, so recreating the instance requires enrolling it again.

On `k8s-manager`, remove the temporary K3s deployment and its Tailscale Service when finished with that part of the lab:

```bash
kubectl delete namespace ops-atlas
kubectl get namespace ops-atlas
```

On `turing-manager`, inspect and stop temporary Docker preview containers that you no longer need. Source files, Git history, and registry images are separate from these running workloads; remove them only when you intend to.

## Git and next milestones

Review changes and push them with:

```bash
git status --short --branch && git log -3 --oneline && git push
```

Keep credentials, Kubernetes Secrets, `.env` files, Terraform state, and saved plans out of Git. Commit `terraform/aws/.terraform.lock.hcl` so provider selection is repeatable. Next lab milestones include a multi-platform image, an idempotent Ansible update path, CI/CD, monitoring, and documented rollback.
