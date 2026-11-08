import { defineConfig } from "vite";

export default defineConfig({
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes("node_modules")) return undefined;
          const normalizedId = id.replaceAll("\\", "/");
          for (const product of ["auth", "firestore", "functions", "storage"]) {
            if (normalizedId.includes(`/firebase/${product}/`) || normalizedId.includes(`/@firebase/${product}/`)) {
              return `firebase-${product}`;
            }
          }
          if (normalizedId.includes("/firebase/") || normalizedId.includes("/@firebase/")) return "firebase-core";
          if (id.includes("/lucide-react/")) return "icons";
          if (id.includes("/react/") || id.includes("/react-dom/") || id.includes("/scheduler/")) return "react-vendor";
          return undefined;
        },
      },
    },
  },
});
