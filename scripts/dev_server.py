#!/usr/bin/env python3

import subprocess
import threading
import signal
from http import HTTPStatus
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import unquote
from pathlib import Path

RENDER_CMD = ["minijinja-cli"]
TEMPLATE_DIR = Path("pages")
PORT = 8000


def render_template(jinja_path: Path) -> bytes | None:
    try:
        result = subprocess.run(
            RENDER_CMD + [str(jinja_path)],
            capture_output=True,
            text=True,
            check=True,
        )
        print(f"✅ Rendered: {jinja_path}")
        return result.stdout.encode("utf-8")
    except subprocess.CalledProcessError as e:
        print(f"❌ Render error: {e}")
        return None


class JinjaRequestHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        raw_path = self.path
        fs_path = TEMPLATE_DIR / unquote(raw_path.lstrip("/"))

        # /dir/ → try /dir/index.jinja2
        jinja_path = fs_path / "index.jinja2"
        if jinja_path.exists():
            return self._render_and_send(jinja_path)

        # /page.html → try /page.jinja2
        if fs_path.suffix == ".html":
            jinja_path = fs_path.with_suffix(".jinja2")
            if jinja_path.exists():
                return self._render_and_send(jinja_path)

        # Try fallback 404 if nothing found
        if not fs_path.exists():
            return self._render_404()

        # Default static file serving
        return super().do_GET()

    def _render_and_send(self, jinja_path: Path):
        html = render_template(jinja_path)
        if html is None:
            return self._render_404()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(html)))
        self.end_headers()
        self.wfile.write(html)

    def _render_404(self):
        jinja_path = TEMPLATE_DIR / "404.jinja2"
        html = render_template(jinja_path)
        if html is None:
            self.send_error(HTTPStatus.NOT_FOUND, "Not Found")
            return
        self.send_response(HTTPStatus.NOT_FOUND)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(html)))
        self.end_headers()
        self.wfile.write(html)


def run_server():
    httpd = HTTPServer(("localhost", PORT), JinjaRequestHandler)

    def shutdown_handler(signum, frame):
        print("\n🧼 Shutting down gracefully...")
        threading.Thread(target=httpd.shutdown).start()

    signal.signal(signal.SIGINT, shutdown_handler)

    print(f"🚀 Dev server running at http://localhost:{PORT}/")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    print("✅ Server stopped")


if __name__ == "__main__":
    run_server()
