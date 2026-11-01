"""Disposable CA + server certificate for simulator-only synthetic HTTPS tests."""
from pathlib import Path
import subprocess

def run(*args):
    subprocess.run(args, check=True)
root=Path('/tmp/phplus-root.cnf')
root.write_text('''[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=phplus disposable simulator test CA
[ext]
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
''')
leaf=Path('/tmp/phplus-leaf.cnf')
leaf.write_text('''basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
''')
run('openssl','req','-x509','-newkey','rsa:2048','-nodes','-sha256','-keyout','/tmp/phplus-root.key','-out','/tmp/phplus-root.crt','-days','1','-config',str(root))
run('openssl','req','-new','-newkey','rsa:2048','-nodes','-sha256','-keyout','/tmp/phplus-fixture.key','-out','/tmp/phplus-fixture.csr','-subj','/CN=localhost')
run('openssl','x509','-req','-in','/tmp/phplus-fixture.csr','-CA','/tmp/phplus-root.crt','-CAkey','/tmp/phplus-root.key','-CAcreateserial','-out','/tmp/phplus-fixture.crt','-days','1','-sha256','-extfile',str(leaf))
run('openssl','x509','-in','/tmp/phplus-root.crt','-outform','der','-out','/tmp/phplus-root.cer')
run('openssl','verify','-CAfile','/tmp/phplus-root.crt','-purpose','sslserver','/tmp/phplus-fixture.crt')
