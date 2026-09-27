"""Verify teardown with read-only AWS CLI calls; bootstrap resources are excluded."""
import json
import os
import subprocess
import time

region = os.environ.get('AWS_REGION', 'eu-central-1')
project = 'aws-devops-portfolio'
checks = {
    'instances': ('describe-instances', 'Reservations'),
    'volumes': ('describe-volumes', 'Volumes'),
    'vpcs': ('describe-vpcs', 'Vpcs'),
    'subnets': ('describe-subnets', 'Subnets'),
    'security_groups': ('describe-security-groups', 'SecurityGroups'),
    'route_tables': ('describe-route-tables', 'RouteTables'),
    'internet_gateways': ('describe-internet-gateways', 'InternetGateways'),
    'elastic_ips': ('describe-addresses', 'Addresses'),
}
def aws(*args):
    return json.loads(subprocess.check_output(['aws', '--region', region, *args, '--output', 'json']))

for attempt in range(30):
    remaining = {}
    for name, (command, key) in checks.items():
        rows = aws('ec2', command, '--filters', f'Name=tag:Project,Values={project}')[key]
        if name == 'instances':
            rows = [instance for row in rows for instance in row['Instances']
                    if instance['State']['Name'] != 'terminated']
        remaining[name] = len(rows)
    groups = aws('logs', 'describe-log-groups', '--log-group-name-prefix', f'/aws/{project}/')['logGroups']
    remaining['cloudwatch_log_groups'] = len(groups)
    print(json.dumps(remaining, sort_keys=True), flush=True)
    if not any(remaining.values()):
        print('AWS CLI verified: no tagged infrastructure remains. Bootstrap S3 and IAM resources are retained.')
        break
    time.sleep(10)
else:
    raise SystemExit('Teardown incomplete: resources remain; inspect the counts above.')
