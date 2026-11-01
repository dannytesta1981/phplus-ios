from http.server import HTTPServer, BaseHTTPRequestHandler
import ssl
class Fixture(BaseHTTPRequestHandler):
    def do_GET(self):
        body=b'<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body><p id="fixtureReady">Synthetic phplus test fixture</p><div style="height:5000px">Scroll test</div></body></html>'
        self.send_response(200)
        self.send_header('Content-Type','text/html; charset=utf-8')
        self.send_header('Content-Length',str(len(body)))
        self.send_header('Cache-Control','no-store')
        self.end_headers();self.wfile.write(body)
server=HTTPServer(('127.0.0.1',8843),Fixture)
context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('/tmp/phplus-fixture.crt','/tmp/phplus-fixture.key')
server.socket=context.wrap_socket(server.socket,server_side=True)
server.serve_forever()
