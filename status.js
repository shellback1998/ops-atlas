const deployments = [
  { target: "local-docker", name: "Local Docker", card: 0 },
  { target: "turing-pi-k3s", name: "Turing Pi K3s", card: 1, url: "http://ops-atlas/api/status" },
  { target: "aws-ec2", name: "AWS Cloud", card: 2, url: "http://ops-atlas-aws:8080/api/status" },
];

async function readStatus(url) {
  const response = await fetch(url, {
    cache: "no-store",
    credentials: "omit",
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

function updateCard(deployment, runtime) {
  const card = document.querySelectorAll(".card")[deployment.card];
  const badge = card.querySelector(".status");
  badge.textContent = runtime ? "● LIVE" : "● UNREACHABLE";
  badge.style.color = runtime ? "#70e0c4" : "#f6b97b";
  badge.title = runtime ? "Status API responded" : "This browser could not reach the status API";

  let details = card.querySelector(".runtime-meta");
  if (!details) {
    details = document.createElement("div");
    details.className = "meta runtime-meta";
    card.append(details);
  }
  details.textContent = runtime
    ? `VERSION ${runtime.version} · HOST ${runtime.hostname}`
    : "Check your Tailscale connection or deployment";
}

let checking = false;
async function refreshDeployments() {
  if (checking) return;
  checking = true;
  try {
    const current = await readStatus("/api/status");
    const currentDeployment = deployments.find((item) => item.target === current.target);
    const banner = document.querySelector("#runtime-banner");
    banner.textContent = `RUNNING ON ${currentDeployment?.name ?? current.target} · VERSION ${current.version}`;
    banner.hidden = false;
    if (currentDeployment) updateCard(currentDeployment, current);

    await Promise.all(
      deployments.filter((item) => item.url && item.target !== current.target).map(async (item) => {
        try {
          const runtime = await readStatus(item.url);
          if (runtime.target !== item.target) throw new Error(`Unexpected target: ${runtime.target}`);
          updateCard(item, runtime);
        } catch (error) {
          console.warn(`Could not check ${item.name}:`, error);
          updateCard(item, null);
        }
      }),
    );
  } catch (error) {
    console.error("Could not identify this deployment:", error);
  } finally {
    checking = false;
  }
}

refreshDeployments();
setInterval(refreshDeployments, 30000);
