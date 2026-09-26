# Ops Atlas

A hybrid application deployment lab spanning Docker, Turing Pi K3s, Git, and a future cloud deployment with Terraform, Ansible, and CI/CD.

## Machines

- `turing-manager`: source code, Docker builds, and Ansible.
- `turing-node01:5000`: local HTTP image registry.
- `k8s-manager`: Kubernetes administration.
- Turing Pi ARM64 workers: run the application.
- `devops-manager`: cloud and Terraform work.

## Application

The dashboard serves `/api/status`, which reports its deployment target, version, pod hostname, and UTC time. The other deployment cards contain sample text until those targets are built.

Current Tailscale URL: http://ops-atlas

## Kubernetes

Manifests are in `k8s/`. Deploy them from `k8s-manager` with `kubectl apply -f /tmp/ops-atlas.yaml -f /tmp/tailscale.yaml`. Check progress with `kubectl rollout status deployment/ops-atlas -n ops-atlas` and `kubectl get pods -n ops-atlas -o wide`.

To remove the lab deployment and its Tailscale Service, run `kubectl delete namespace ops-atlas`. Source files and registry images remain available.

## Git workflow

After committing changes, run `git status --short --branch && git log -3 --oneline && git push` to check, review, and push in one line.

Keep credentials, Kubernetes Secrets, Terraform state, and local environment files out of Git.
