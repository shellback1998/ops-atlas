async function showRuntime() {
  try {
    const response = await fetch("/api/status", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const runtime = await response.json();

    const cardIndex = runtime.target === "turing-pi-k3s" ? 1 : 0;
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
