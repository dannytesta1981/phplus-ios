"""Synthetic HTTPS provider/portal routes. No real account or verification."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import ssl
class Fixture(BaseHTTPRequestHandler):
    def redirect(self, destination, code=302):
        self.send_response(code)
        self.send_header('Location',destination)
        self.send_header('Content-Length','0')
        self.end_headers()
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length','0')))
        if self.path == '/verify-submit':
            return self.redirect('https://localhost:8843/scan-complete',303)
        self.send_error(404)
    def do_GET(self):
        if self.path == '/verify-start':
            return self.redirect('https://127.0.0.1:8843/verify-hop')
        if self.path == '/verify-hop':
            return self.redirect('https://localhost:8843/scan-complete')
        if self.path == '/preview.mp4':
            body=Path('Tests/preview.mp4').read_bytes(); content='video/mp4'
        else:
            extra=''
            if self.path == '/capture-context':
                extra='''<script>window.webkit.messageHandlers.fixtureCapture.postMessage('context')</script><iframe allow="camera; microphone" src="https://127.0.0.1:8843/capture-frame"></iframe>'''
            elif self.path == '/capture-frame':
                extra='''<script>window.webkit.messageHandlers.fixtureCapture.postMessage('context')</script>'''
            elif self.path == '/preview':
                extra='''<video id="preview" muted playsinline loop preload="auto" src="/preview.mp4"></video>'''
            body=('''<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body><p id="fixtureReady">Synthetic phplus test fixture</p>'''+extra+'''<div style="height:5000px">Scroll test</div></body></html>''').encode()
            content='text/html; charset=utf-8'
        self.send_response(200)
        self.send_header('Content-Type',content)
        self.send_header('Content-Length',str(len(body)))
        self.send_header('Cache-Control','no-store')
        self.end_headers();self.wfile.write(body)
server=ThreadingHTTPServer(('127.0.0.1',8843),Fixture)
context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('/tmp/phplus-fixture.crt','/tmp/phplus-fixture.key')
server.socket=context.wrap_socket(server.socket,server_side=True)
server.serve_forever()
