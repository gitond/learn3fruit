// Specifying build instructions for Vite
// Must include WebAssembly parts of LiteRT.js in build.
import { defineConfig } from 'vite';
import { viteStaticCopy } from 'vite-plugin-static-copy';

export default defineConfig({
  plugins: [
    viteStaticCopy({
      targets: [
        {
          src: 'node_modules/@mediapipe/tasks-vision/wasm/*',
          dest: 'wasm',
          rename: {
            stripBase: true // DO NOT COPY ENTIRE node_modules/... STRUCTURE
          }
        }
      ]
    })
  ]
});
