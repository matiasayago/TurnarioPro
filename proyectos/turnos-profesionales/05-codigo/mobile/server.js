const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 8092;
const buildPath = path.join(__dirname, 'build/web');

const server = http.createServer((req, res) => {
  let filePath = path.join(buildPath, req.url === '/' ? 'index.html' : req.url);
  
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('Not Found');
      return;
    }
    
    let contentType = 'text/html';
    if (filePath.endsWith('.js')) contentType = 'application/javascript';
    if (filePath.endsWith('.css')) contentType = 'text/css';
    if (filePath.endsWith('.wasm')) contentType = 'application/wasm';
    if (filePath.endsWith('.json')) contentType = 'application/json';
    if (filePath.endsWith('.png')) contentType = 'image/png';
    if (filePath.endsWith('.svg')) contentType = 'image/svg+xml';
    
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(data);
  });
});

server.listen(PORT, () => {
  console.log(`✓ Servidor en http://localhost:${PORT}`);
});
