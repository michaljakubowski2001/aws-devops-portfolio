"""Publish non-secret bootstrap outputs as GitHub variables after local bootstrap."""
import json
import subprocess

config = json.loads(subprocess.check_output(['terraform', '-chdir=bootstrap', 'output', '-json', 'configuration']))
for name, value in config.items():
    subprocess.run(['gh', 'variable', 'set', name, '--body', str(value)], check=True)
print('Variables configured. AWS_READY remains disabled until you explicitly enable it.')
