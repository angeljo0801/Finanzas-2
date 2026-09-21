import base64, io, os, tarfile
from pathlib import Path

root = Path.cwd() / "finanzas_definitiva"
payload_dir = Path.cwd() / "payload"
payload = "".join((payload_dir / f"chunk_{i:02d}.txt").read_text(encoding="utf-8").strip() for i in range(7))
data = base64.b64decode(payload)
with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tf:
    tf.extractall(root)
print("Applied Finance AI flexibility/copy bundle")
