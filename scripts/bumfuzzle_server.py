#!/usr/bin/env python3
import http.server, json, os, shutil, socketserver, subprocess, tempfile

PORT      = int(os.environ['BUMFUZZLE_PORT'])
PROJ_DIR  = os.environ['BUMFUZZLE_PROJECT_DIR']
RUN_SH    = os.environ['BUMFUZZLE_RUN_SH']
HTML_PATH = os.environ['BUMFUZZLE_HTML']
YAML_PATH     = os.path.join(PROJ_DIR, '.bumfuzzle', 'config.yml')
SETTINGS_PATH = os.environ['BUMFUZZLE_SETTINGS']
# RUN_SH is BUMFUZZLE_ROOT/scripts/run.sh (wizard.sh), so its directory is
# where the prerequisite check scripts actually live - never PROJ_DIR, which
# is the arbitrary target project being edited and has no scripts/ of its own.
SCRIPTS_DIR = os.path.dirname(RUN_SH)

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
            # unique per request: ThreadingServer handles concurrent POSTs on
            # separate threads, and a fixed shared filename here raced two
            # overlapping /save calls against the same temp file.
            tmp_fd, tmp_path = tempfile.mkstemp(
                suffix='.tmp', prefix='config.yml.', dir=os.path.dirname(YAML_PATH),
            )
            with os.fdopen(tmp_fd, 'wb') as f:
                f.write(body)
            errs = []
            # validate-schema.sh predates the [FAIL:tier] convention the other
            # two use and reports plain "[FAIL] " lines instead (see its own
            # header comment) - both forms are treated as findings here.
            for check in ('script-args.sh', 'script-arg-types.sh', 'validate-schema.sh'):
                proc = subprocess.run(
                    [os.path.join(SCRIPTS_DIR, 'prerequisites', check), tmp_path],
                    capture_output=True, text=True,
                )
                errs += [l for l in proc.stdout.splitlines() if l.startswith('[FAIL:') or l.startswith('[FAIL] ')]
            if errs:
                os.remove(tmp_path)
                msg = '\n'.join(e.split('] ', 1)[-1] for e in errs).encode()
                self.send_response(400)
                self.send_header('Content-Type', 'text/plain; charset=utf-8')
                self.send_header('Content-Length', str(len(msg)))
                self.end_headers()
                self.wfile.write(msg)
                return
            os.replace(tmp_path, YAML_PATH)
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
