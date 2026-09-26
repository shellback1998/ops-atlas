# Ops Atlas

Ops Atlas is a hybrid deployment lab. One application runs on a Turing Pi K3s cluster (ARM64) and an AWS EC2 instance (AMD64). The dashboard checks both `/api/status` endpoints from your browser and refreshes their cards every 30 seconds.

## Current deployment

| Environment | Dashboard | API | Runtime |
| --- | --- | --- | --- |
| Turing Pi K3s | <http://ops-atlas> | <http://ops-atlas/api/status> | Kubernetes pod on an ARM64 worker |
| AWS EC2 | <http://ops-atlas-aws:8080> | <http://ops-atlas-aws:8080/api/status> | Docker on Amazon Linux 2023 AMD64 |

These names work from devices connected to the tailnet; they are not public internet addresses. An `UNREACHABLE` card reports what **your browser** could reach. It does not by itself prove that the remote app is down. Each API response identifies the target, deployed version, container or pod hostname, and UTC time.

The deployed version is now `sha-` plus the first seven characters of the Git commit that triggered delivery. For example, `sha-844d534` on both APIs shows they came from the same CI run. The images are selected by the full OCI digest returned by the publish job.

## Hosts and responsibilities

| Host or service | Responsibility |
| --- | --- |
| GitHub Actions | Test the app, publish one multi-platform GHCR image, then deploy to K3s and AWS |
| GitHub Container Registry | Store the AMD64 and ARM64 variants under the same image digest |
| `k8s-manager` | Kubernetes administration and manual inspections |
| Turing Pi ARM64 workers | Run the K3s app; no GitHub runner or GitOps controller installed |
| `devops-manager` | Keep Terraform state, run Terraform and optional Ansible maintenance |
| `ops-atlas-aws` | EC2 Docker host, registered with Tailscale and Systems Manager |

## What a push does

`.github/workflows/ci.yml` runs on a push to `main`, a pull request to `main`, or manual dispatch:

1. `build-and-smoke-test` checks Python syntax, builds and starts a test container, and checks the page, JavaScript, and status API.
2. `publish-image` runs after tests on a push to `main`. It publishes Linux AMD64 and ARM64 variants to `ghcr.io/shellback1998/ops-atlas` and passes the image digest to the deployment jobs.
3. `deploy-k3s` joins the tailnet as a temporary GitHub-hosted runner, updates the `ops-atlas` Deployment to that digest, sets `APP_VERSION=sha-...`, and waits for the rollout.
4. `deploy-aws` runs after K3s succeeds. GitHub OIDC assumes a dedicated AWS IAM role and uses Systems Manager to run `scripts/deploy-aws-ssm.sh` on the one EC2 instance. The script pulls the same digest, verifies AMD64, replaces the container when necessary, and retries the local status API until it reports the expected version.

No self-hosted runner is installed on the lab machines. AWS deployment uses Systems Manager; it does not require a public inbound SSH or app port. The EC2 host must remain online in Systems Manager and be able to pull the public GHCR image.

To inspect the latest run from a machine with an authenticated GitHub CLI:

```bash
gh run list --workflow ci.yml --limit 3
```

Copy the numeric ID of the desired run from that list, then run `gh run view` or `gh run watch` with that ID. To verify the two endpoints from a tailnet-connected machine:

```bash
curl -sS http://ops-atlas/api/status
curl -sS http://ops-atlas-aws:8080/api/status
```

If AWS delivery fails after K3s succeeds, the K3s deployment stays on the new version. Inspect the failed GitHub job and both API responses before retrying. A workflow rerun rebuilds and republishes its commit and then attempts both deployments again.

## Deployment credentials and scope

| Credential or identity | Storage and access |
| --- | --- |
| `TS_OAUTH_CLIENT_ID`, `TS_AUDIENCE` | GitHub Actions repository secrets for temporary tailnet access |
| `K3S_DEPLOY_TOKEN`, `K3S_CA_B64` | GitHub Actions repository secrets; token authenticates the `ops-atlas-deployer` ServiceAccount and CA verifies K3s TLS |
| `ops-atlas-deployer` | K3s ServiceAccount with `get`, `patch`, and `watch` on the `ops-atlas` Deployment only; no permission to read Kubernetes Secrets |
| `ops-atlas-github-deploy` | Terraform-managed IAM role assumed using GitHub OIDC for this repository's `main` branch; can send `AWS-RunShellScript` only to the Ops Atlas EC2 instance and read command results |

The Kubernetes token is held in an `ops-atlas-deployer-token` Secret in the `ops-atlas` namespace. It is long lived: rotate or delete the GitHub secret and the K3s Secret when access is no longer needed. Never commit a token, populated kubeconfig, Terraform state, or saved plan. The **manifest that creates** a Kubernetes token Secret can be stored outside the repository without containing the generated token.

The Terraform AWS role is limited to one instance, but `AWS-RunShellScript` runs commands as root **on that instance**. Restrict who can edit the GitHub workflow and who can push to `main`.

## Application and infrastructure files

| File | Purpose |
| --- | --- |
| `index.html`, `status.js`, `server.py`, `Dockerfile` | Dashboard, live status behavior, API, and container image |
| `k8s/ops-atlas.yaml`, `k8s/tailscale.yaml` | Baseline K3s Deployment and Services |
| `terraform/aws/main.tf` | Existing EC2 instance and network selections |
| `terraform/aws/github-deploy.tf` | GitHub OIDC provider, restricted AWS role, and SSM policy |
| `scripts/deploy-aws-ssm.sh` | Idempotent EC2 container deployment and health check |
| `.github/workflows/ci.yml` | CI, publishing, K3s delivery, and AWS delivery |
| `.github/workflows/tailnet-connectivity.yml` | Manual connectivity test for a temporary tailnet runner |
| `ansible/bootstrap-aws.yml` | Install and start Docker on the EC2 host |
| `ansible/deploy-aws.yml` | Earlier manual deployment path using a selected GHCR digest |

The currently committed `k8s/ops-atlas.yaml` pins an older image digest as a baseline for manual recovery. **Applying that manifest directly can roll the running app back.** Normal releases use the GitHub Actions deployment job. If you apply the manifest manually, first set its image and `APP_VERSION` to the intended release.

## Work locally

On `turing-manager` or another host with Docker, in this repository:

```bash
docker build -t ops-atlas:local .
docker run --rm -d --name ops-atlas-local -p 8083:8080 \
  -e DEPLOYMENT_TARGET=local-docker -e APP_VERSION=local ops-atlas:local
curl http://localhost:8083/api/status
docker stop ops-atlas-local
```

The local HTTP registry on `turing-node01:5000` was used for earlier ARM64 lab releases. Current automatic releases use GHCR instead.

## Earlier manual deployment path

The original lab built the ARM64 app on `turing-manager`, pushed it to the local HTTP registry, and applied manifests on `k8s-manager`. That still demonstrates the individual steps; the CI/CD workflow now handles routine releases. For an isolated manual test, choose a **new** image tag. Before copying the manifest, update its image and `APP_VERSION` to that tag and version. Applying it changes the live deployment:

```bash
# turing-manager
docker buildx build --platform linux/arm64 \
  -t 192.168.8.191:5000/ops-atlas:manual-arm64 --load .
docker push 192.168.8.191:5000/ops-atlas:manual-arm64
scp k8s/ops-atlas.yaml k8s/tailscale.yaml piadmin@k8s-manager:/tmp/
```

Then, on `k8s-manager`:

```bash
kubectl apply -f /tmp/ops-atlas.yaml -f /tmp/tailscale.yaml
kubectl rollout status deployment/ops-atlas -n ops-atlas --timeout=180s
```

The original AWS lab used Tailscale SSH and Ansible from `devops-manager`. Its playbook remains useful for practicing configuration management; it is a separate manual deployment path from CI/CD:

```bash
ansible aws -i ansible/inventory.ini -m ping
ansible-playbook -i ansible/inventory.ini ansible/bootstrap-aws.yml
ansible-playbook -i ansible/inventory.ini ansible/deploy-aws.yml
```

`ansible/deploy-aws.yml` pins its own older digest. Running it now can replace the CI/CD version on AWS. Update that digest deliberately when practicing manual deployment, then push `main` again to return both targets to a matched CI/CD release. The older `build-aws.yml` and `run-aws.yml` are retained as separate learning steps.

## Inspect and maintain the running systems

On `k8s-manager`:

```bash
kubectl rollout status deployment/ops-atlas -n ops-atlas --timeout=180s
kubectl get pods -n ops-atlas -o wide
kubectl get deployment ops-atlas -n ops-atlas \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

On `devops-manager`:

```bash
terraform -chdir=terraform/aws output
aws ssm describe-instance-information \
  --filters Key=InstanceIds,Values=i-054c9cecfd2dbc1a4 \
  --query 'InstanceInformationList[].[InstanceId,PingStatus]' --output table
```

Terraform state is local to `devops-manager` and must be retained to manage or destroy the EC2 and IAM resources. Tailscale enrollment on the EC2 host was performed manually; it is not part of Terraform.

## Cleanup and revocation

This lab's EC2 instance, volume, and public IPv4 address can incur charges while allocated. When ending the AWS lab, plan and destroy from the **same** `devops-manager` Terraform state:

```bash
terraform -chdir=terraform/aws plan -destroy
terraform -chdir=terraform/aws destroy
terraform -chdir=terraform/aws state list
```

Destroying Terraform resources also removes this lab's GitHub OIDC provider and deployment role. Confirm the EC2 instance is gone and remove its `ops-atlas-aws` device from the Tailscale admin console; Terraform does not remove that manually enrolled device. Recreating the host requires Tailscale enrollment and Docker bootstrap again. Once AWS is destroyed, later pushes to `main` will make the AWS deployment job fail until the host is recreated or the workflow is changed.

To end the K3s lab on `k8s-manager`, delete the `ops-atlas` namespace. This also deletes the deployment ServiceAccount and its token Secret:

```bash
kubectl delete namespace ops-atlas
```

Remove the now-unused repository secrets through GitHub Settings or `gh secret delete K3S_DEPLOY_TOKEN --repo shellback1998/ops-atlas` (and the other three listed above) when retiring the pipeline. Keep the GitHub repository and source unless you intend to remove them.

## Git workflow

Review recent commits and push in one command:

```bash
git status --short --branch && git log -3 --oneline && git push
```

Commit `terraform/aws/.terraform.lock.hcl` for repeatable provider selection. Keep `.terraform/`, `*.tfstate`, saved Terraform plans, credentials, and generated Kubernetes tokens out of Git.
