#!/usr/bin/env bash
# bumfuzzle.sh — browser-based project scaffolding (wraps kickstart.sh)
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do SOURCE="$(readlink "$SOURCE")"; done
KICKSTART_REPO="$(cd "$(dirname "$SOURCE")" && pwd)"
KICKSTART_SH="$KICKSTART_REPO/kickstart.sh"
PREFLIGHT_SH="$KICKSTART_REPO/preflight.sh"
SETTINGS="$KICKSTART_REPO/bumfuzzle-template.yml"
BUMFUZZLE_HTML="$KICKSTART_REPO/index.html"
BUMFUZZLE_VERSION="$(cat "$KICKSTART_REPO/VERSION" 2>/dev/null || printf 'unknown')"
PORT=7373

if ! command -v yq &>/dev/null; then
  printf 'Error: yq is required\n' >&2; exit 1
fi
if ! command -v python3 &>/dev/null; then
  printf 'Error: python3 is required\n' >&2; exit 1
fi
if [[ ! -f "$BUMFUZZLE_HTML" ]]; then
  printf 'Error: bumfuzzle template not found: %s\n' "$BUMFUZZLE_HTML" >&2; exit 1
fi
if lsof -i ":$PORT" -sTCP:LISTEN -t &>/dev/null 2>&1; then
  printf 'Error: port %d is already in use\n' "$PORT" >&2; exit 1
fi

PROJECT_DIR="$(pwd)"
PROJECT_DIR_NAME="$(basename "$PROJECT_DIR")"

# ── Create bumfuzzle.yml with defaults if not present ─────────────────────────

if [[ ! -f "$PROJECT_DIR/bumfuzzle.yml" ]]; then
  cp "$SETTINGS" "$PROJECT_DIR/bumfuzzle.yml"
  yq -i ".project.name = \"$PROJECT_DIR_NAME\"" "$PROJECT_DIR/bumfuzzle.yml"
  printf '  Created bumfuzzle.yml\n'
fi

# ── Build CONFIG JSON ──────────────────────────────────────────────────────────

SETTINGS_JSON=$(yq -o=json '.' "$SETTINGS")
CURRENT_JSON=$(yq -o=json '.' "$PROJECT_DIR/bumfuzzle.yml" 2>/dev/null || printf '{}')

CONFIG_JSON=$(printf '{"settings":%s,"current":%s,"meta":{"projectDir":"%s","projectDirName":"%s","version":"%s"}}' \
  "$SETTINGS_JSON" "$CURRENT_JSON" \
  "$PROJECT_DIR" "$PROJECT_DIR_NAME" "$BUMFUZZLE_VERSION")

# ── Write Python HTTP server to temp file ─────────────────────────────────────

PYTHON_SRV="/tmp/bumfuzzle_server_$$.py"

cat > "$PYTHON_SRV" << 'PYEOF'
import http.server, json, os, socketserver, subprocess

PORT      = int(os.environ['BUMFUZZLE_PORT'])
PROJ_DIR  = os.environ['BUMFUZZLE_PROJECT_DIR']
KS_SH     = os.environ['BUMFUZZLE_KICKSTART_SH']
PF_SH     = os.environ['BUMFUZZLE_PREFLIGHT_SH']
HTML_PATH = os.environ['BUMFUZZLE_HTML']
CFG_BYTES = os.environ['BUMFUZZLE_CONFIG_JSON'].encode()
YAML_PATH = os.path.join(PROJ_DIR, 'bumfuzzle.yml')

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass

    def do_GET(self):
        if self.path in ('/', '/index.html'):
            with open(HTML_PATH, 'rb') as f:
                data = f.read()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif self.path == '/config':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(CFG_BYTES)))
            self.end_headers()
            self.wfile.write(CFG_BYTES)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body   = self.rfile.read(length)
        if self.path == '/save':
            with open(YAML_PATH, 'wb') as f:
                f.write(body)
            self.send_response(200)
            self.end_headers()
        elif self.path in ('/run/kickstart', '/run/preflight'):
            script = KS_SH if self.path == '/run/kickstart' else PF_SH
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('X-Accel-Buffering', 'no')
            self.end_headers()
            try:
                proc = subprocess.Popen(
                    [script], cwd=PROJ_DIR,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                )
                for line in proc.stdout:
                    msg = ('data: ' + json.dumps(line.rstrip('\n')) + '\n\n').encode()
                    self.wfile.write(msg)
                    self.wfile.flush()
                proc.wait()
                done = ('data: ' + json.dumps('__DONE__ ' + str(proc.returncode)) + '\n\n').encode()
                self.wfile.write(done)
                self.wfile.flush()
            except Exception:
                try:
                    self.wfile.write(b'data: "__DONE__ 1"\n\n')
                    self.wfile.flush()
                except Exception:
                    pass
        else:
            self.send_response(404)
            self.end_headers()

class ThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

ThreadingServer(('127.0.0.1', PORT), Handler).serve_forever()
PYEOF

# ── Export env vars for Python server ─────────────────────────────────────────

export BUMFUZZLE_PORT="$PORT"
export BUMFUZZLE_PROJECT_DIR="$PROJECT_DIR"
export BUMFUZZLE_KICKSTART_SH="$KICKSTART_SH"
export BUMFUZZLE_PREFLIGHT_SH="$PREFLIGHT_SH"
export BUMFUZZLE_HTML
export BUMFUZZLE_CONFIG_JSON="$CONFIG_JSON"

# ── Start server ──────────────────────────────────────────────────────────────

python3 "$PYTHON_SRV" &
_server_pid=$!
trap 'kill "$_server_pid" 2>/dev/null; rm -f "$PYTHON_SRV"' EXIT

printf '\n  bumfuzzle v%s\n' "$BUMFUZZLE_VERSION"
printf '  %s\n\n' "$(printf '%.0s─' {1..48})"
printf '  Project: %s\n' "$PROJECT_DIR"
printf '  Serving: http://localhost:%d\n' "$PORT"
printf '  Press Ctrl+C to exit.\n\n'

sleep 0.5
open "$PROJECT_DIR"
open "http://localhost:$PORT"

# ── Wait (Ctrl+C cancels cleanly) ─────────────────────────────────────────────

wait "$_server_pid" || true
