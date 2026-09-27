locals {
  regional = { StringEquals = { "aws:RequestedRegion" = var.region } }
  tagged   = { StringEquals = { "aws:RequestedRegion" = var.region, "ec2:ResourceTag/Project" = var.project } }
  creation = { StringEquals = { "aws:RequestedRegion" = var.region, "aws:RequestTag/Project" = var.project } }
  read_statements = [
    {
      Sid      = "RegionalDiscovery", Effect = "Allow"
      Action   = ["ec2:Describe*", "ssm:DescribeInstanceInformation", "logs:DescribeLogGroups"]
      Resource = "*", Condition = local.regional
    },
    {
      Sid      = "ProjectLogMetadata", Effect = "Allow"
      Action   = ["logs:ListTagsForResource", "logs:ListTagsLogGroup", "logs:DescribeLogStreams"]
      Resource = [local.log_arn, "${local.log_arn}:*"]
    },
    {
      Sid      = "StateBucketMetadata", Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation"]
      Resource = aws_s3_bucket.state.arn
    },
    {
      Sid      = "ReadInfraState", Effect = "Allow", Action = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.state.arn}/infra/terraform.tfstate"
    },
    {
      Sid      = "CoordinateInfraLock", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = "${aws_s3_bucket.state.arn}/infra/terraform.tfstate.tflock"
    },
    {
      Sid      = "InspectInstanceProfile", Effect = "Allow", Action = ["iam:GetInstanceProfile"]
      Resource = aws_iam_instance_profile.app.arn
    }
  ]
  deploy_statements = [
    {
      Sid      = "WriteInfraState", Effect = "Allow", Action = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.state.arn}/infra/terraform.tfstate"
    },
    {
      Sid      = "CreateTaggedNetwork", Effect = "Allow"
      Action   = ["ec2:CreateVpc", "ec2:CreateSubnet", "ec2:CreateInternetGateway", "ec2:CreateRouteTable", "ec2:CreateSecurityGroup"]
      Resource = "*", Condition = local.creation
    },
    {
      Sid = "ManageTaggedResources", Effect = "Allow"
      Action = [
        "ec2:DeleteVpc", "ec2:ModifyVpcAttribute", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
        "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DeleteInternetGateway",
        "ec2:DeleteRouteTable", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
        "ec2:CreateRoute", "ec2:ReplaceRoute", "ec2:DeleteRoute", "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress", "ec2:ModifySecurityGroupRules",
        "ec2:TerminateInstances", "ec2:ModifyInstanceAttribute", "ec2:ModifyInstanceMetadataOptions",
        "ec2:ModifyInstanceCreditSpecification", "ec2:StopInstances", "ec2:StartInstances",
        "ec2:CreateTags", "ec2:DeleteTags"
      ]
      Resource = "${local.ec2_arn}:*", Condition = local.tagged
    },
    {
      Sid      = "TagAtCreation", Effect = "Allow", Action = ["ec2:CreateTags"]
      Resource = "${local.ec2_arn}:*"
      Condition = { StringEquals = {
        "aws:RequestTag/Project" = var.project
        "ec2:CreateAction"       = ["CreateVpc", "CreateSubnet", "CreateInternetGateway", "CreateRouteTable", "CreateSecurityGroup", "RunInstances", "AuthorizeSecurityGroupEgress"]
      } }
    },
    {
      Sid       = "LaunchTaggedCompute", Effect = "Allow", Action = ["ec2:RunInstances"]
      Resource  = ["${local.ec2_arn}:instance/*", "${local.ec2_arn}:volume/*"]
      Condition = { StringEquals = { "aws:RequestedRegion" = var.region, "aws:RequestTag/Project" = var.project } }
    },
    {
      Sid       = "LaunchOnlySmallInstances", Effect = "Deny", Action = ["ec2:RunInstances"]
      Resource  = "${local.ec2_arn}:instance/*"
      Condition = { StringNotEquals = { "ec2:InstanceType" = "t3.small" } }
    },
    {
      Sid       = "UseTaggedNetwork", Effect = "Allow", Action = ["ec2:RunInstances"]
      Resource  = ["${local.ec2_arn}:subnet/*", "${local.ec2_arn}:security-group/*"]
      Condition = local.tagged
    },
    {
      Sid       = "LaunchImageAndInterface", Effect = "Allow", Action = ["ec2:RunInstances"]
      Resource  = ["arn:aws:ec2:${var.region}::image/ami-*", "${local.ec2_arn}:network-interface/*"]
      Condition = local.regional
    },
    {
      Sid       = "PassOnlyProjectInstanceRole", Effect = "Allow", Action = ["iam:PassRole"]
      Resource  = aws_iam_role.instance.arn
      Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
    },
    {
      Sid      = "ManageProjectLogs", Effect = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource"]
      Resource = [local.log_arn, "${local.log_arn}:*"]
    },
    {
      Sid       = "ConnectOnlyTaggedInstances", Effect = "Allow", Action = ["ssm:StartSession"]
      Resource  = "${local.ec2_arn}:instance/*"
      Condition = { StringEquals = { "ssm:resourceTag/Project" = var.project } }
    },
    {
      Sid = "UseSessionDocuments", Effect = "Allow", Action = ["ssm:StartSession"]
      Resource = [
        "arn:aws:ssm:${var.region}::document/AWS-StartInteractiveCommand",
        "arn:aws:ssm:${var.region}::document/AWS-StartPortForwardingSession",
        "arn:aws:ssm:${var.region}:${local.account_id}:document/SSM-SessionManagerRunShell"
      ]
    },
    {
      Sid      = "EndOwnCISessions", Effect = "Allow", Action = ["ssm:TerminateSession", "ssm:ResumeSession"]
      Resource = "arn:aws:ssm:${var.region}:${local.account_id}:session/portfolio-*"
    },
    {
      Sid      = "TransferBucketMetadata", Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"]
      Resource = aws_s3_bucket.transfer.arn
    },
    {
      Sid      = "AnsibleEphemeralTransfers", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = "${aws_s3_bucket.transfer.arn}/i-*/*"
    }
  ]
}
resource "aws_iam_role_policy" "github" {
  for_each = aws_iam_role.github
  name     = "${each.key}-portfolio"
  role     = each.value.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat(local.read_statements, [for statement in local.deploy_statements : statement if each.key == "deploy"])
  })
}
