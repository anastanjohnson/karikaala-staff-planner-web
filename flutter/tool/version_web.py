"""Give each Flutter release immutable entrypoint filenames for browser caches."""
from pathlib import Path
import hashlib
import re

root = Path('build/web')
main = root / 'main.dart.js'
version = hashlib.sha256(main.read_bytes()).hexdigest()[:16]
main_name = f'main.dart.{version}.js'
(root / main_name).write_bytes(main.read_bytes())
bootstrap = (root / 'flutter_bootstrap.js').read_text()
bootstrap = bootstrap.replace('"mainJsPath":"main.dart.js"', f'"mainJsPath":"{main_name}"')
assert main_name in bootstrap
bootstrap_name = f'flutter_bootstrap.{version}.js'
(root / bootstrap_name).write_text(bootstrap)
index = root / 'index.html'
index.write_text(index.read_text().replace('src="flutter_bootstrap.js"', f'src="{bootstrap_name}"'))
print(f'Versioned web release: {version}')
