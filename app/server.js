const http = require('http');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const PORT = 80;
const OLLAMA_URL = 'http://localhost:11434';
const S3_BUCKET = 'REPLACE_WITH_S3_BUCKET';

// VULNERABILITY: No input validation or sanitization
function processYouTubeUrl(url, callback) {
  // VULNERABILITY: Command injection possible through URL
  const command = `yt-dlp --extractor-args "youtube:player_client=default" --skip-download --write-auto-sub --sub-lang en --sub-format json3 --output "subtitle" "${url}" 2>&1 || yt-dlp --extractor-args "youtube:player_client=default" --skip-download --print description "${url}"`;

  exec(command, { maxBuffer: 1024 * 1024 * 10 }, (error, stdout, stderr) => {
    if (error && !stdout) {
      // Fallback: try to get description only
      exec(`yt-dlp --skip-download --print description "${url}"`, (err2, stdout2) => {
        if (err2) {
          callback(null, 'Unable to fetch video content. Using URL as context.');
          return;
        }
        callback(null, stdout2);
      });
      return;
    }

    // Try to read subtitle file if it exists
    const subtitleFile = 'subtitle.en.json3';
    if (fs.existsSync(subtitleFile)) {
      const subtitleData = fs.readFileSync(subtitleFile, 'utf8');
      try {
        const json = JSON.parse(subtitleData);
        const transcript = json.events
          .filter(e => e.segs)
          .map(e => e.segs.map(s => s.utf8).join(''))
          .join(' ');
        fs.unlinkSync(subtitleFile);
        callback(null, transcript);
      } catch (e) {
        callback(null, stdout);
      }
    } else {
      callback(null, stdout);
    }
  });
}

// VULNERABILITY: Prompt injection - user input directly concatenated
function summarizeWithOllama(content, userPrompt, callback) {
  // VULNERABILITY: No sanitization of user input allows prompt injection
  const prompt = `${userPrompt}\n\nVideo Content:\n${content}\n\nProvide a summary:`;

  const data = JSON.stringify({
    model: 'llama3.2',
    prompt: prompt,
    stream: false
  });

  const options = {
    hostname: 'localhost',
    port: 11434,
    path: '/api/generate',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': data.length
    }
  };

  const req = http.request(options, (res) => {
    let responseData = '';

    res.on('data', (chunk) => {
      responseData += chunk;
    });

    res.on('end', () => {
      try {
        const jsonResponse = JSON.parse(responseData);
        callback(null, jsonResponse.response);
      } catch (e) {
        callback(e, null);
      }
    });
  });

  req.on('error', (e) => {
    callback(e, null);
  });

  req.write(data);
  req.end();
}

// VULNERABILITY: Exposed endpoint to list S3 bucket contents
function listS3Contents(callback) {
  exec(`aws s3 ls s3://${S3_BUCKET}/ --recursive`, (error, stdout, stderr) => {
    if (error) {
      callback(error, null);
      return;
    }
    callback(null, stdout);
  });
}

// VULNERABILITY: Exposed endpoint to read S3 files
function readS3File(key, callback) {
  exec(`aws s3 cp s3://${S3_BUCKET}/${key} -`, (error, stdout, stderr) => {
    if (error) {
      callback(error, null);
      return;
    }
    callback(null, stdout);
  });
}

// VULNERABILITY: Exposed endpoint to get EC2 metadata (including IAM credentials)
function getMetadata(path, callback) {
  const url = `http://169.254.169.254/latest/${path}`;
  exec(`curl -s ${url}`, (error, stdout, stderr) => {
    if (error) {
      callback(error, null);
      return;
    }
    callback(null, stdout);
  });
}

const server = http.createServer((req, res) => {
  // CORS headers - VULNERABILITY: Allows any origin
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // Serve static files
  if (req.method === 'GET' && req.url === '/') {
    fs.readFile(path.join(__dirname, 'index.html'), (err, data) => {
      if (err) {
        res.writeHead(500);
        res.end('Error loading page');
        return;
      }
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(data);
    });
    return;
  }

  // API endpoint for video summarization
  if (req.method === 'POST' && req.url === '/api/summarize') {
    let body = '';

    req.on('data', chunk => {
      body += chunk.toString();
    });

    req.on('end', () => {
      try {
        const { url, customPrompt } = JSON.parse(body);

        // VULNERABILITY: No URL validation
        processYouTubeUrl(url, (err, content) => {
          if (err) {
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Failed to process video' }));
            return;
          }

          const promptToUse = customPrompt || 'Summarize the following video content';

          summarizeWithOllama(content, promptToUse, (err, summary) => {
            if (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: 'Failed to generate summary' }));
              return;
            }

            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ summary }));
          });
        });
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid request' }));
      }
    });
    return;
  }

  // VULNERABILITY: Exposed S3 listing endpoint
  if (req.method === 'GET' && req.url === '/api/s3/list') {
    listS3Contents((err, contents) => {
      if (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Failed to list S3 contents' }));
        return;
      }
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end(contents);
    });
    return;
  }

  // VULNERABILITY: Exposed S3 file reading endpoint
  if (req.method === 'POST' && req.url === '/api/s3/read') {
    let body = '';

    req.on('data', chunk => {
      body += chunk.toString();
    });

    req.on('end', () => {
      try {
        const { key } = JSON.parse(body);
        readS3File(key, (err, content) => {
          if (err) {
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Failed to read S3 file' }));
            return;
          }
          res.writeHead(200, { 'Content-Type': 'text/plain' });
          res.end(content);
        });
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid request' }));
      }
    });
    return;
  }

  // VULNERABILITY: Exposed metadata endpoint (SSRF)
  if (req.method === 'POST' && req.url === '/api/metadata') {
    let body = '';

    req.on('data', chunk => {
      body += chunk.toString();
    });

    req.on('end', () => {
      try {
        const { path } = JSON.parse(body);
        getMetadata(path, (err, data) => {
          if (err) {
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Failed to get metadata' }));
            return;
          }
          res.writeHead(200, { 'Content-Type': 'text/plain' });
          res.end(data);
        });
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid request' }));
      }
    });
    return;
  }

  res.writeHead(404);
  res.end('Not found');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Vulnerable AI application running on port ${PORT}`);
  console.log('WARNING: This application is intentionally insecure for training purposes');
});
