provider "aws" {
}


#- Step 0: Upload the s32s3 configuration file to the buckets
# cbdt stands for the "Cross border data transfer"
resource "aws_s3_bucket" "confBucket" {
  bucket = join("-", ["cbdt", replace(lower(var.DataSetName), "_", "-"), "conf"])
}


resource "aws_s3_bucket_object" "s32s3-conf" {
  bucket = aws_s3_bucket.confBucket.bucket
  key    = "s32s3.conf"
  source = "./s32s3.conf"
  etag   = filemd5("./s32s3.conf")
}


#- Step 1: Create the Elastic Container Registry and Cluster
data "aws_caller_identity" "current" {}


resource "aws_ecr_repository" "s32s3" {
  name = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "s32s3"]))

  provisioner "local-exec" {
    working_dir = ".terraform/modules/s32s3/s32s3-Docker"
    command     = " aws ecr get-login-password --region cn-north-1 | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.cn-north-1.amazonaws.com.cn"
  }

  provisioner "local-exec" {
    working_dir = ".terraform/modules/s32s3/s32s3-Docker"
    command     = "docker build -t ${aws_ecr_repository.s32s3.name} ."
  }

  provisioner "local-exec" {
    working_dir = ".terraform/modules/s32s3/s32s3-Docker"
    command     = "docker tag ${aws_ecr_repository.s32s3.name}:latest ${data.aws_caller_identity.current.account_id}.dkr.ecr.cn-north-1.amazonaws.com.cn/${aws_ecr_repository.s32s3.name}:latest"
  }

  provisioner "local-exec" {
    working_dir = ".terraform/modules/s32s3/s32s3-Docker"
    command     = "docker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.cn-north-1.amazonaws.com.cn/${aws_ecr_repository.s32s3.name}:latest"
  }
}


resource "aws_ecs_cluster" "ECS-DT-Clu" {
  name = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "clu"]))
}


resource "aws_cloudwatch_log_group" "loggroup" {
  name              = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "loggroup"]))
  retention_in_days = 14
}


data "aws_ecr_image" "s32s3-image" {
  repository_name = aws_ecr_repository.s32s3.name
  image_tag       = "latest"
}


data "aws_region" "current" {}


resource "aws_iam_role" "role_for_ecs_task" {
  name = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "role-for-ecs-task"]))
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ecs-tasks.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}


resource "aws_iam_policy" "policy_for_ecs_task" {
  name        = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "policy-for-ecs-task"]))
  path        = "/"
  description = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "policy-for-ecs-task"]))
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : "s3:*",
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "*"
      },
      {
        "Action" : [
          "secretsmanager:*",
          "cloudformation:CreateChangeSet",
          "cloudformation:DescribeChangeSet",
          "cloudformation:DescribeStackResource",
          "cloudformation:DescribeStacks",
          "cloudformation:ExecuteChangeSet",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "kms:DescribeKey",
          "kms:ListAliases",
          "kms:ListKeys",
          "lambda:ListFunctions",
          "tag:GetResources"
        ],
        "Effect" : "Allow",
        "Resource" : "*"
      }
    ]
  })
}


resource "aws_iam_policy_attachment" "ecs-task-policy-role-attach" {
  name       = join("-", ["cbdt", var.DataSetName, "ecs-task-policy-role-attachment"])
  roles      = [aws_iam_role.role_for_ecs_task.name]
  policy_arn = aws_iam_policy.policy_for_ecs_task.arn
}


resource "aws_ecs_task_definition" "s32s3" {
  family                   = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "s32s3"]))
  task_role_arn            = aws_iam_role.role_for_ecs_task.arn
  execution_role_arn       = aws_iam_role.role_for_ecs_task.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  container_definitions = jsonencode([
    {
      name      = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "s32s3-c1"]))
      image     = join(":", [aws_ecr_repository.s32s3.repository_url, "latest"])
      essential = true
      "environment" : [
        {
          "name" : "SecretName",
          "value" : aws_secretsmanager_secret.Secret-s32s3.name
        },
        {
          "name" : "JobConf",
          "value" : "${aws_s3_bucket.confBucket.bucket}/${aws_s3_bucket_object.s32s3-conf.key}"
        },
        {
          "name" : "Region",
          "value" : data.aws_region.current.name
        }
      ],
      "logConfiguration" : {
        "logDriver" : "awslogs",
        "options" : {
          "awslogs-region" : data.aws_region.current.name,
          "awslogs-group" : aws_cloudwatch_log_group.loggroup.name,
          "awslogs-stream-prefix" : "${var.DataSetName}-s32s3"
        }
      }
    }
  ])
}


#- Step 2: Create the secrets to save the senstive informatioon

resource "aws_secretsmanager_secret" "Secret-s32s3" {
  name                    = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "secret-s32s3"]))
  recovery_window_in_days = 0
}


variable "s32s3_keys" {
  default = {
    src_access_key_id     = "Replace Me using your aws access key"
    src_secret_access_key = "Replace Me using your aws access secret key"
    dst_access_key_id     = "Replace Me using your aws access key"
    dst_secret_access_key = "Replace Me using your aws access secret key"
  }
  type = map(string)
}


resource "aws_secretsmanager_secret_version" "Secret-s32s3-version" {
  secret_id     = aws_secretsmanager_secret.Secret-s32s3.id
  secret_string = jsonencode(var.s32s3_keys)
}


#- Step 3: Create the Cloudwatch Event rule to trigger the lambda and ECS task.
data "aws_ecs_cluster" "ECS-DT-Clu" {
  cluster_name = aws_ecs_cluster.ECS-DT-Clu.name
}


data "aws_ecs_task_definition" "s32s3" {
  task_definition = aws_ecs_task_definition.s32s3.family
}


resource "aws_iam_role" "CW-Invoke-ECS-Role" {
  name = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "CW-Invoke-ECS-Role"]))
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "events.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}


resource "aws_iam_policy" "CW-Invoke-ECS-Role-Policy" {
  name        = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "CW-Invoke-ECS-Role-Policy"]))
  path        = "/"
  description = join("-", ["cbdt", var.DataSetName, "CW-Invoke-ECS-Role-Policy"])
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ecs:RunTask"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : "iam:PassRole",
        "Resource" : "*",
        "Condition" : {
          "StringLike" : {
            "iam:PassedToService" : "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}


resource "aws_iam_policy_attachment" "cw-invoke-ecs-policy-role-attach" {
  name       = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "cw-invoke-ecs-policy-role-attachment"]))
  roles      = [aws_iam_role.CW-Invoke-ECS-Role.name]
  policy_arn = aws_iam_policy.CW-Invoke-ECS-Role-Policy.arn
}


resource "aws_cloudwatch_event_rule" "TriggerS32S3Task-Rule" {
  name                = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "Trigger-S32S3-Rule"]))
  description         = "Trigger the ECS Task to transfer data between src S3 and dst S3"
  schedule_expression = "cron(0 0 * * ? *)"
}


resource "aws_cloudwatch_event_target" "TriggerS32S3Task-Rule-Target" {
  target_id = lower(join("-", ["cbdt", replace(var.DataSetName, "_", "-"), "cloudwatch-s32s3-target"]))
  arn       = aws_ecs_cluster.ECS-DT-Clu.arn
  role_arn  = aws_iam_role.CW-Invoke-ECS-Role.arn
  rule      = aws_cloudwatch_event_rule.TriggerS32S3Task-Rule.name
  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.s32s3.arn
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = var.subnetIDs
      security_groups  = var.securityGroups
      assign_public_ip = true
    }
  }
}
