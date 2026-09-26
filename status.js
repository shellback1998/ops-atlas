async function showRuntime() {
  try {
    const response = await fetch("/api/status", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const runtime = await response.json();

    const cardIndex = {
      "local-docker": 0,
      "turing-pi-k3s": 1,
      "aws-ec2": 2,
    }[runtime.target];
    const labels = {
      "local-docker": "Local Docker",
      "turing-pi-k3s": "Turing Pi K3s",
      "aws-ec2": "AWS Cloud",
    };
    const banner = document.querySelector("#runtime-banner");
    banner.textContent = `RUNNING ON ${labels[runtime.target]} · VERSION ${runtime.version}`;
    banner.hidden = false;

    const card = document.querySelectorAll(".card")[cardIndex];
    card.querySelector(".status").textContent = "● LIVE";

    const details = document.createElement("div");
    details.className = "meta";
    details.textContent = `VERSION ${runtime.version} · HOST ${runtime.hostname}`;
    card.append(details);
  } catch (error) {
    console.error("Could not load runtime status:", error);
  }
}

showRuntime();
