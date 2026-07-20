#!/usr/bin/env python3
import http.server, json, os, shutil, socketserver, subprocess

PORT      = int(os.environ['BUMFUZZLE_PORT'])
PROJ_DIR  = os.environ['BUMFUZZLE_PROJECT_DIR']
RUN_SH    = os.environ['BUMFUZZLE_RUN_SH']
HTML_PATH = os.environ['BUMFUZZLE_HTML']
YAML_PATH     = os.path.join(PROJ_DIR, '.bumfuzzle', 'config.yml')
SETTINGS_PATH = os.environ['BUMFUZZLE_SETTINGS']

current_cfg = [os.environ['BUMFUZZLE_CONFIG_JSON'].encode()]

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
            data = current_cfg[0]
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body   = self.rfile.read(length)
        if self.path == '/save':
            with open(YAML_PATH, 'wb') as f:
                f.write(body)
            try:
                new_current = subprocess.check_output(['yq', '-o=json', '.', YAML_PATH], text=True)
                old_cfg = json.loads(current_cfg[0].decode())
                old_cfg['current'] = json.loads(new_current)
                current_cfg[0] = json.dumps(old_cfg).encode()
            except Exception:
                pass
            self.send_response(200)
            self.end_headers()
        elif self.path == '/reset':
            shutil.copy(SETTINGS_PATH, YAML_PATH)
            try:
                new_current = subprocess.check_output(['yq', '-o=json', '.', YAML_PATH], text=True)
                old_cfg = json.loads(current_cfg[0].decode())
                old_cfg['current'] = json.loads(new_current)
                current_cfg[0] = json.dumps(old_cfg).encode()
            except Exception:
                pass
            self.send_response(200)
            self.end_headers()
        elif self.path in ('/run', '/run/verbose'):
            argv = [RUN_SH, '--verbose'] if self.path == '/run/verbose' else [RUN_SH]
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('X-Accel-Buffering', 'no')
            self.end_headers()
            try:
                proc = subprocess.Popen(
                    argv, cwd=PROJ_DIR,
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

try:
    ThreadingServer(('127.0.0.1', PORT), Handler).serve_forever()
except KeyboardInterrupt:
    pass
