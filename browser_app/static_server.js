import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const publicDirectory = path.join(__dirname, 'dist');
const port = 8080;

const mimeTypes = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.wasm': 'application/wasm',
    '.tflite': 'application/octet-stream',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.svg': 'image/svg+xml',
};

const server = http.createServer((request, response) => {
    let requestPath;

    try {
        requestPath = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    } catch {
        response.writeHead(400);
        response.end('Bad request');
        return;
    }

    const filePath = path.normalize(
        path.join(publicDirectory, requestPath === '/' ? 'index.html' : requestPath)
    );

    // Prevent requests from escaping the public directory.
    if (!filePath.startsWith(publicDirectory)) {
        response.writeHead(403);
        response.end('Forbidden');
        return;
    }

    fs.stat(filePath, (statError, stats) => {
        if (statError || !stats.isFile()) {
            response.writeHead(404);
            response.end('Not found');
            return;
        }

        const extension = path.extname(filePath).toLowerCase();
        const contentType = mimeTypes[extension] ?? 'application/octet-stream';

        response.writeHead(200, {
            'Content-Type': contentType,
        });

        fs.createReadStream(filePath).pipe(response);
    });
});

server.listen(port, '0.0.0.0', () => {
    console.log(`Static server running on http://localhost:${port}`);
});
