let leafletAssetsPromise = null;

// The chat button sits over every map's bottom-right corner, where Leaflet
// puts the OpenStreetMap credit the tiles must show. Every map starts with
// the credit bottom-left instead.
function configureLeaflet(L) {
  if (L?.Control?.Attribution) {
    L.Control.Attribution.prototype.options.position = "bottomleft";
  }
  return L;
}

export async function loadLeafletAssets() {
  if (typeof window === "undefined") {
    return null;
  }
  if (window.L) {
    return configureLeaflet(window.L);
  }
  if (!leafletAssetsPromise) {
    leafletAssetsPromise = new Promise((resolve, reject) => {
      if (!document.querySelector('link[data-leaflet-runtime="true"]')) {
        const stylesheet = document.createElement("link");
        stylesheet.rel = "stylesheet";
        stylesheet.href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
        stylesheet.dataset.leafletRuntime = "true";
        document.head.appendChild(stylesheet);
      }
      const existingScript = document.querySelector('script[data-leaflet-runtime="true"]');
      if (existingScript) {
        existingScript.addEventListener("load", () => resolve(configureLeaflet(window.L)), { once: true });
        existingScript.addEventListener("error", () => reject(new Error("Unable to load Leaflet map assets.")), { once: true });
        return;
      }
      const script = document.createElement("script");
      script.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
      script.async = true;
      script.dataset.leafletRuntime = "true";
      script.onload = () => resolve(configureLeaflet(window.L));
      script.onerror = () => reject(new Error("Unable to load Leaflet map assets."));
      document.body.appendChild(script);
    });
  }
  return leafletAssetsPromise;
}
