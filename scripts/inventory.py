"""Create a narrow inventory from Terraform outputs, never a broad EC2 discovery."""
import json
import re
import subprocess
from pathlib import Path

outputs = json.loads(subprocess.check_output(['terraform', '-chdir=infra', 'output', '-json']))
instance = outputs['instance_id']['value']
if not re.fullmatch(r'i-[a-f0-9]+', instance):
    raise SystemExit('Unexpected instance ID')
Path('ansible/inventory/generated.yml').write_text(json.dumps({
    'all': {'children': {'portfolio': {'hosts': {'aws': {'ansible_host': instance}}}}}
}, indent=2) + '\n')
print(f'Inventory targets one EC2 instance: {instance}')
