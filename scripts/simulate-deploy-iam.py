"""Simulate every AWS call the deploy role makes for infra apply, Ansible over SSM and destroy.

Runs against the live policy with realistic resource ARNs and condition context, so
authorization gaps show up before a CI run instead of as a 403 halfway through an apply.
Uses the operator's local credentials (iam:SimulatePrincipalPolicy); it changes nothing.
"""
import sys

import boto3

REGION = 'eu-central-1'
PROJECT = 'aws-devops-portfolio'
sts = boto3.client('sts')
iam = boto3.client('iam')
account = sts.get_caller_identity()['Account']
role_arn = f'arn:aws:iam::{account}:role/{PROJECT}-deploy'
ec2 = f'arn:aws:ec2:{REGION}:{account}'
transfer = f'arn:aws:s3:::{PROJECT}-{account}-{REGION}-transfer'
state = f'arn:aws:s3:::{PROJECT}-{account}-{REGION}-state'
logs = f'arn:aws:logs:{REGION}:{account}:log-group:/aws/{PROJECT}/system'


def ctx(**keys):
    entries = [{'ContextKeyName': 'aws:RequestedRegion', 'ContextKeyValues': [REGION], 'ContextKeyType': 'string'}]
    for name, value in keys.items():
        entries.append({'ContextKeyName': name.replace('__', ':').replace('_S_', '/'),
                        'ContextKeyValues': [value], 'ContextKeyType': 'string'})
    return entries


new = dict(aws__RequestTag_S_Project=PROJECT)              # resource being created with tags
own = {'ec2__ResourceTag_S_Project': PROJECT}               # existing project resource
foreign = {'ec2__ResourceTag_S_Project': 'someone-else'}    # existing unrelated resource

# (label, action, resource ARN, context, expected decision)
CASES = [
    # Subnet
    ('subnet', 'ec2:CreateSubnet', f'{ec2}:subnet/*', ctx(**new), 'allowed'),
    ('subnet', 'ec2:CreateSubnet', f'{ec2}:vpc/vpc-0713fe4dbb1912147', ctx(**own), 'allowed'),
    ('subnet', 'ec2:CreateTags', f'{ec2}:subnet/*', ctx(**new, ec2__CreateAction='CreateSubnet'), 'allowed'),
    ('subnet', 'ec2:ModifySubnetAttribute', f'{ec2}:subnet/subnet-0', ctx(**own), 'allowed'),
    # Route table, route and association
    ('route table', 'ec2:CreateRouteTable', f'{ec2}:route-table/*', ctx(**new), 'allowed'),
    ('route table', 'ec2:CreateRouteTable', f'{ec2}:vpc/vpc-0713fe4dbb1912147', ctx(**own), 'allowed'),
    ('route table', 'ec2:CreateTags', f'{ec2}:route-table/*', ctx(**new, ec2__CreateAction='CreateRouteTable'), 'allowed'),
    ('route table', 'ec2:CreateRoute', f'{ec2}:route-table/rtb-0', ctx(**own), 'allowed'),
    ('association', 'ec2:AssociateRouteTable', f'{ec2}:route-table/rtb-0', ctx(**own), 'allowed'),
    ('association', 'ec2:AssociateRouteTable', f'{ec2}:subnet/subnet-0', ctx(**own), 'allowed'),
    # Security group and egress rules (the provider revokes AWS's default allow-all egress)
    ('security group', 'ec2:CreateSecurityGroup', f'{ec2}:security-group/*', ctx(**new), 'allowed'),
    ('security group', 'ec2:CreateSecurityGroup', f'{ec2}:vpc/vpc-0713fe4dbb1912147', ctx(**own), 'allowed'),
    ('security group', 'ec2:CreateTags', f'{ec2}:security-group/*', ctx(**new, ec2__CreateAction='CreateSecurityGroup'), 'allowed'),
    ('security group', 'ec2:RevokeSecurityGroupEgress', f'{ec2}:security-group/sg-0', ctx(**own), 'allowed'),
    ('egress rules', 'ec2:AuthorizeSecurityGroupEgress', f'{ec2}:security-group/sg-0', ctx(**own), 'allowed'),
    ('egress rules', 'ec2:AuthorizeSecurityGroupEgress', f'{ec2}:security-group-rule/*', ctx(**new), 'allowed'),
    ('egress rules', 'ec2:CreateTags', f'{ec2}:security-group-rule/*', ctx(**new, ec2__CreateAction='AuthorizeSecurityGroupEgress'), 'allowed'),
    # Instance launch: every resource type RunInstances authorizes, plus the instance profile role
    ('instance', 'ec2:RunInstances', f'{ec2}:instance/*', ctx(**new, ec2__InstanceType='t3.small'), 'allowed'),
    ('instance', 'ec2:RunInstances', f'{ec2}:volume/*', ctx(**new), 'allowed'),
    ('instance', 'ec2:RunInstances', f'{ec2}:subnet/subnet-0', ctx(**own), 'allowed'),
    ('instance', 'ec2:RunInstances', f'{ec2}:security-group/sg-0', ctx(**own), 'allowed'),
    ('instance', 'ec2:RunInstances', f'{ec2}:network-interface/*', ctx(), 'allowed'),
    ('instance', 'ec2:RunInstances', f'arn:aws:ec2:{REGION}::image/ami-0b8a830d6339a9758', ctx(), 'allowed'),
    ('instance', 'ec2:CreateTags', f'{ec2}:instance/*', ctx(**new, ec2__CreateAction='RunInstances'), 'allowed'),
    ('instance', 'ec2:CreateTags', f'{ec2}:volume/*', ctx(**new, ec2__CreateAction='RunInstances'), 'allowed'),
    ('instance profile', 'iam:PassRole', f'arn:aws:iam::{account}:role/{PROJECT}-instance',
     ctx(iam__PassedToService='ec2.amazonaws.com'), 'allowed'),
    ('instance', 'ec2:DescribeInstances', '*', ctx(), 'allowed'),
    ('instance', 'ec2:DescribeInstanceAttribute', '*', ctx(), 'allowed'),
    ('instance', 'ec2:DescribeInstanceCreditSpecifications', '*', ctx(), 'allowed'),
    ('instance', 'ec2:ModifyInstanceCreditSpecification', f'{ec2}:instance/i-0', ctx(**own), 'allowed'),
    # State
    ('state', 's3:PutObject', f'{state}/infra/terraform.tfstate', ctx(), 'allowed'),
    ('state', 's3:PutObject', f'{state}/infra/terraform.tfstate.tflock', ctx(), 'allowed'),
    ('state', 's3:DeleteObject', f'{state}/infra/terraform.tfstate.tflock', ctx(), 'allowed'),
    # Ansible over SSM and smoke-test tunnels
    ('ssm', 'ssm:StartSession', f'{ec2}:instance/i-0', ctx(ssm__resourceTag_S_Project=PROJECT), 'allowed'),
    ('ssm', 'ssm:StartSession', f'arn:aws:ssm:{REGION}:{account}:document/SSM-SessionManagerRunShell', ctx(), 'allowed'),
    ('ssm', 'ssm:StartSession', f'arn:aws:ssm:{REGION}::document/AWS-StartPortForwardingSession', ctx(), 'allowed'),
    ('ssm', 'ssm:TerminateSession', f'arn:aws:ssm:{REGION}:{account}:session/portfolio-deploy-1-abc', ctx(), 'allowed'),
    ('transfer', 's3:PutObject', f'{transfer}/i-0//tmp/ansible-module.py', ctx(), 'allowed'),
    ('transfer', 's3:GetObject', f'{transfer}/i-0//tmp/ansible-module.py', ctx(), 'allowed'),
    ('transfer', 's3:DeleteObject', f'{transfer}/i-0//tmp/ansible-module.py', ctx(), 'allowed'),
    # Destroy
    ('destroy', 'ec2:TerminateInstances', f'{ec2}:instance/i-0', ctx(**own), 'allowed'),
    ('destroy', 'ec2:DisassociateRouteTable', f'{ec2}:route-table/rtb-0', ctx(**own), 'allowed'),
    ('destroy', 'ec2:DisassociateRouteTable', f'{ec2}:subnet/subnet-0', ctx(**own), 'allowed'),
    ('destroy', 'ec2:DeleteRouteTable', f'{ec2}:route-table/rtb-0', ctx(**own), 'allowed'),
    ('destroy', 'ec2:DeleteSubnet', f'{ec2}:subnet/subnet-0', ctx(**own), 'allowed'),
    # RevokeSecurityGroupEgress authorizes only the security-group resource type.
    ('destroy', 'ec2:RevokeSecurityGroupEgress', f'{ec2}:security-group/sg-0', ctx(**own), 'allowed'),
    ('destroy', 'ec2:DeleteSecurityGroup', f'{ec2}:security-group/sg-0', ctx(**own), 'allowed'),
    ('destroy', 'ec2:DetachInternetGateway', f'{ec2}:internet-gateway/igw-0', ctx(**own), 'allowed'),
    ('destroy', 'ec2:DetachInternetGateway', f'{ec2}:vpc/vpc-0713fe4dbb1912147', ctx(**own), 'allowed'),
    ('destroy', 'ec2:DeleteInternetGateway', f'{ec2}:internet-gateway/igw-0', ctx(**own), 'allowed'),
    ('destroy', 'ec2:DeleteVpc', f'{ec2}:vpc/vpc-0713fe4dbb1912147', ctx(**own), 'allowed'),
    ('destroy', 'logs:DeleteLogGroup', logs, ctx(), 'allowed'),
    # Boundaries that must stay closed
    ('boundary', 'ec2:RunInstances', f'{ec2}:instance/*', ctx(**new, ec2__InstanceType='m5.large'), 'explicitDeny'),
    ('boundary', 'ec2:RunInstances', f'{ec2}:instance/*', ctx(ec2__InstanceType='t3.small'), 'implicitDeny'),
    ('boundary', 'ec2:CreateSubnet', f'{ec2}:vpc/vpc-foreign', ctx(**foreign), 'implicitDeny'),
    ('boundary', 'ec2:TerminateInstances', f'{ec2}:instance/i-foreign', ctx(**foreign), 'implicitDeny'),
    ('boundary', 'ec2:AuthorizeSecurityGroupIngress', f'{ec2}:security-group/sg-0', ctx(**own), 'implicitDeny'),
    ('boundary', 'ec2:AllocateAddress', f'{ec2}:elastic-ip/*', ctx(**new), 'implicitDeny'),
    ('boundary', 'ec2:CreateNatGateway', f'{ec2}:natgateway/*', ctx(**new), 'implicitDeny'),
    ('boundary', 'iam:CreateRole', f'arn:aws:iam::{account}:role/anything', ctx(), 'implicitDeny'),
    ('boundary', 'iam:PassRole', f'arn:aws:iam::{account}:role/{PROJECT}-deploy',
     ctx(iam__PassedToService='ec2.amazonaws.com'), 'implicitDeny'),
    ('boundary', 's3:PutObject', f'{state}/bootstrap/terraform.tfstate', ctx(), 'implicitDeny'),
    ('boundary', 'ssm:StartSession', f'{ec2}:instance/i-foreign', ctx(ssm__resourceTag_S_Project='someone-else'), 'implicitDeny'),
]

failures = 0
for label, action, resource, context, expected in CASES:
    result = iam.simulate_principal_policy(
        PolicySourceArn=role_arn, ActionNames=[action], ResourceArns=[resource], ContextEntries=context,
    )['EvaluationResults'][0]
    decision = result['EvalDecision']
    ok = decision == expected
    failures += not ok
    missing = result.get('MissingContextValues') or []
    note = f'  missing context: {missing}' if missing and not ok else ''
    print(f"{'PASS' if ok else 'FAIL'}  {label:16} {action:40} {decision:13} {resource.split(':')[-1][:48]}{note}")

print(f'\n{len(CASES) - failures}/{len(CASES)} checks match expectations.')
sys.exit(1 if failures else 0)
