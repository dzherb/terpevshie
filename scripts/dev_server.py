# /// script
# dependencies = [
#   "watchdog",
#   "websockets",
# ]
# ///

import asyncio
import subprocess
import threading
import signal
from pathlib import Path
from http import HTTPStatus
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import unquote

import websockets
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

RENDER_CMD = ["minijinja-cli"]
TEMPLATE_DIR = Path("pages")
PORT = 8000
WS_PORT = 8765

clients = set()


def render_template(jinja_path: Path) -> bytes | None:
    try:
        result = subprocess.run(
            RENDER_CMD + [str(jinja_path)],
            capture_output=True,
            text=True,
            check=True,
        )
        print(f"✅ Rendered: {jinja_path}")
        html = result.stdout

        # Inject live reload script before </body>
        if "</body>" in html:
            html = html.replace(
                "</body>",
                f'<script src="/__livereload.js"></script></body>',
            )
        return html.encode("utf-8")
    except subprocess.CalledProcessError as e:
        print(f"❌ Render error: {e}")
        return None


class JinjaRequestHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        raw_path = self.path
        if raw_path == "/__livereload.js":
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/javascript")
            self.end_headers()
            self.wfile.write(LIVERELOAD_JS.encode())
            return

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

        # Try fallback 404
        if not fs_path.exists():
            return self._render_404()

        # Serve static file (e.g. CSS or image)
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


# ========== Live Reload JS ==========
LIVERELOAD_JS = f"""
const ws = new WebSocket("ws://localhost:{WS_PORT}");
ws.onmessage = () => window.location.reload();
console.log("[LiveReload] listening...");
""".strip()


# ========== WebSocket Server ==========
async def ws_handler(websocket):
    clients.add(websocket)
    try:
        await websocket.wait_closed()
    finally:
        clients.remove(websocket)


def start_ws_server():
    async def run():
        async with websockets.serve(ws_handler, "localhost", WS_PORT):
            print(f"🔁 WebSocket server running at ws://localhost:{WS_PORT}/")
            await asyncio.Future()

    threading.Thread(target=lambda: asyncio.run(run()), daemon=True).start()


# ========== Watchdog ==========
class ReloadEventHandler(FileSystemEventHandler):
    def on_modified(self, event):
        if event.is_directory:
            return

        print(f"🔄 Change detected: {event.src_path}")
        asyncio.run(send_reload())


async def send_reload():
    if not clients:
        return
    await asyncio.gather(*[client.send("reload") for client in clients])


def start_watchdog():
    observer = Observer()
    observer.schedule(ReloadEventHandler(), TEMPLATE_DIR, recursive=True)
    observer.start()
    return observer


# ========== HTTP Server ==========
def run_server():
    httpd = HTTPServer(("localhost", PORT), JinjaRequestHandler)

    def shutdown_handler(signum, frame):
        print("\n🧼 Shutting down gracefully...")
        observer.stop()
        threading.Thread(target=httpd.shutdown).start()

    signal.signal(signal.SIGINT, shutdown_handler)

    print(f"🚀 Dev server running at http://localhost:{PORT}/")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    print("✅ Server stopped")


if __name__ == "__main__":
    start_ws_server()
    observer = start_watchdog()
    run_server()
