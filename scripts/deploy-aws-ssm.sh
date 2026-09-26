# Runs on the EC2 host as root using SSM AWS-RunShellScript.
# IMAGE_REF and RELEASE_SHA are set by the GitHub Actions job.
set -eu

case "$IMAGE_REF" in
  ghcr.io/shellback1998/ops-atlas@sha256:*) ;;
  *) echo 'Unexpected image reference' >&2; exit 1 ;;
esac

release_version="sha-$(printf '%.7s' "$RELEASE_SHA")"
docker pull "$IMAGE_REF"
desired_id="$(docker image inspect --format '{{.Id}}' "$IMAGE_REF")"
architecture="$(docker image inspect --format '{{.Architecture}}' "$IMAGE_REF")"
test "$architecture" = amd64

existing_id="$(docker container inspect --format '{{.Image}}' ops-atlas-aws 2>/dev/null || true)"
running="$(docker container inspect --format '{{.State.Running}}' ops-atlas-aws 2>/dev/null || true)"

if [ "$existing_id" = "$desired_id" ] && [ "$running" = true ] && \
   docker container inspect --format '{{range .Config.Env}}{{println .}}{{end}}' ops-atlas-aws |
     grep -Fx "APP_VERSION=$release_version" >/dev/null; then
  echo 'Ops Atlas already runs the requested image and version'
else
  if [ -n "$existing_id" ]; then
    docker rm -f ops-atlas-aws
  fi
  docker run -d --name ops-atlas-aws --restart unless-stopped \
    -p 8080:8080 \
    -e DEPLOYMENT_TARGET=aws-ec2 \
    -e "APP_VERSION=$release_version" \
    "$IMAGE_REF"
fi

curl --fail --silent --show-error --retry 12 --retry-connrefused \
  --retry-delay 2 http://127.0.0.1:8080/api/status |
  EXPECTED_VERSION="$release_version" python3 -c 'import json,os,sys; s=json.load(sys.stdin); assert s["target"] == "aws-ec2" and s["version"] == os.environ["EXPECTED_VERSION"], s; print("Ops Atlas AWS:", s["version"], s["hostname"])'
