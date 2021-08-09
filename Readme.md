[toc]

# S32S3 module introduction

## Which tools are involed
- Terraform
- rclone
- Amazon ECS
- Amazon SecretsManager
- Python
- Docker
  
## Security
Your sensitive information will be saved into SecretsManager. 
- access key
- access secret key

## Terraform module structure
- s32s3.tf, main module which integrates all block together.
- variables.tf, define the variables which you need to provide for this module.
- s32s3-Docker, which includes the ECR images defination.
- Doc, which includes the module configuration doc.
- conf, which includes the s32s3 configuration.

## Depyloment
![](/img/deployment.png)

## How to use this module

### Step 1

This module still does follow the design keynote, everything kicks off from the dataset. 
- Dataset name
- Source
  - S3 bucket name
  - KMS arn
  - access_key
  - secret_access_key
  - region
- Destination 
  - S3 bucket name
  - KMS arn
  - access_key
  - secret_access_key
  - region

### Step 2
Download the [terraform](https://www.terraform.io/downloads.html)

### Step 3
Create the directory to include your terraform file.
```hcl
module "s32s3" {
  source = "/Users/picomy/Playground/S32S3-tf"

  DataSetName = "dataset-5"
  
  vpcID          = "vpc-0d680669"
  subnetIDs      = ["subnet-eabc819d", "subnet-17388b73"]
  securityGroups = ["sg-0b70322a890ba7ef1"]
}
```

Copy the s32s3.conf from s32s3-tf/conf into your current directory.

### Step 4

The s32s3.conf defines the cross border data transfer.
```ini
[src-s3]
type = s3
provider = AWS
env_auth = false
access_key_id =
secret_access_key =
region = cn-north-1
endpoint = s3.cn-north-1.amazonaws.com.cn
location_constraint = cn-north-1
acl = bucket-owner-full-control
server_side_encryption = 
sse_kms_key_id = 

[dst-s3]
type = s3
provider = AWS
env_auth = false
access_key_id =
secret_access_key =
region = cn-north-1
endpoint = s3.cn-north-1.amazonaws.com.cn
location_constraint = cn-north-1
acl = bucket-owner-full-control
server_side_encryption = 
sse_kms_key_id = 

[Replication]
src_path = dataset-2
dst_path = datarep-dst-1
```

### Step 5 

```shell
export AWS_DEFAULT_REGION=cn-north-1
terraform init
terraform plan
terraform apply
```

### Step 6
Login to your cloud account, and access the Secrets Manager, you will see the following secrets:
- cbdt-{datasetname}-secret-s32s3

update your src and dest s3 aksk.


## FAQ

### How to change the ingest frequency?
Login to your cloud account, and access the Cloudwatch/Events/Rule/{datasetname}-Trigger-SFTP2S3-Rule,change the setting.

### Whether does it support accessing cross the account?
Yes.
