(() => {
  const playlistUrl = "assets/videos/playlist.json";
  const videoDir = "assets/videos/";
  const player = document.getElementById("adVideoPlayer");
  const source = document.createElement("source");
  const fallback = document.getElementById("videoPlaylistFallback");
  let playlist = [];
  let currentIndex = 0;

  if (!player) {
    return;
  }

  source.id = "adVideoSource";
  player.appendChild(source);
  player.muted = true;
  player.autoplay = true;
  player.playsInline = true;
  player.loop = false;
  player.controls = false;

  const guessMime = (fileName) => {
    const ext = (fileName.split(".").pop() || "").toLowerCase();
    if (ext === "mp4" || ext === "m4v") return "video/mp4";
    if (ext === "webm") return "video/webm";
    if (ext === "ogg" || ext === "ogv") return "video/ogg";
    return "";
  };

  const showFallback = (message) => {
    if (fallback) {
      fallback.textContent = message;
      fallback.classList.add("is-visible");
    }
  };

  const hideFallback = () => {
    if (fallback) {
      fallback.classList.remove("is-visible");
    }
  };

  const normalizeEntry = (entry) => {
    if (!entry) return null;
    if (typeof entry === "string") {
      return { src: videoDir + entry, type: guessMime(entry) };
    }
    if (typeof entry === "object" && entry.src) {
      const isAbsolute = /^https?:\/\//i.test(entry.src) || entry.src.startsWith("/");
      const src = isAbsolute ? entry.src : videoDir + entry.src;
      return { src, type: entry.type || guessMime(entry.src) };
    }
    return null;
  };

  const playIndex = (index) => {
    if (!playlist.length) {
      return;
    }

    currentIndex = (index + playlist.length) % playlist.length;
    const { src, type } = playlist[currentIndex];

    source.src = src;
    source.type = type || "";
    player.load();
    player.play().catch((err) => {
      console.error("Autoplay fehlgeschlagen, Interaktion nötig?", err);
      showFallback("Autoplay blockiert – bitte Browser-Interaktion erlauben.");
    });
  };

  const nextVideo = () => {
    if (!playlist.length) return;
    playIndex(currentIndex + 1);
  };

  player.addEventListener("ended", nextVideo);
  player.addEventListener("error", nextVideo);

  fetch(playlistUrl, { cache: "no-store" })
    .then((res) => {
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return res.json();
    })
    .then((data) => {
      const list =
        data && Array.isArray(data.videos)
          ? data.videos
          : Array.isArray(data)
          ? data
          : [];

      playlist = list.map(normalizeEntry).filter(Boolean);

      if (!playlist.length) {
        showFallback("Keine Videos gefunden. Bitte Dateien in assets/videos/ ablegen.");
        return;
      }

      hideFallback();
      playIndex(0);
    })
    .catch((err) => {
      console.error("Video-Playlist konnte nicht geladen werden", err);
      showFallback("Video-Playlist konnte nicht geladen werden.");
    });
})();
