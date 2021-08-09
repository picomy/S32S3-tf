import configparser
import subprocess
import os
import boto3
import base64
from botocore.exceptions import ClientError
import json


def get_secret(secretstore):

    secret_name = secretstore
    region_name = "cn-north-1"

    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    # In this sample we only handle the specific exceptions for the 'GetSecretValue' API.
    # See https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
    # We rethrow the exception by default.

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
    except ClientError as e:
        if e.response['Error']['Code'] == 'DecryptionFailureException':
            # Secrets Manager can't decrypt the protected secret text using the provided KMS key.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InternalServiceErrorException':
            # An error occurred on the server side.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InvalidParameterException':
            # You provided an invalid value for a parameter.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InvalidRequestException':
            # You provided a parameter value that is not valid for the current state of the resource.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'ResourceNotFoundException':
            # We can't find the resource that you asked for.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
    else:
        # Decrypts secret using the associated KMS CMK.
        # Depending on whether the secret is a string or binary, one of these fields will be populated.
        if 'SecretString' in get_secret_value_response:
            secret = get_secret_value_response['SecretString']
            return secret
        else:
            decoded_binary_secret = base64.b64decode(get_secret_value_response['SecretBinary'])
            return decoded_binary_secret


# Get the Job classified information from Secrets Manager
secret_name = os.getenv("SecretName")
secretResult = get_secret(secret_name)

secretDict = json.loads(secretResult)
src_aws_ak = secretDict["src_access_key_id"]
src_aws_sk = secretDict["src_secret_access_key"]
dst_aws_ak = secretDict["dst_access_key_id"]
dst_aws_sk = secretDict["dst_secret_access_key"]

# Copy the JobConf into Container
region = os.getenv("Region")
rconf = "s3://" + os.getenv("JobConf")
subprocess.run(['mkdir', '-p', '/root/.config/rclone'])
subprocess.run(['aws','--region', region, 's3', 'cp', rconf, '/root/.config/rclone/rclone.conf'])

# Update rclone remote system's attribute
conf = configparser.ConfigParser()
conf.read("/root/.config/rclone/rclone.conf")

## Update the s3 ak&sk
conf["src-s3"]["access_key_id"] = src_aws_ak
conf["src-s3"]["secret_access_key"] = src_aws_sk
conf["dst-s3"]["access_key_id"] = dst_aws_ak
conf["dst-s3"]["secret_access_key"] = dst_aws_sk

# Read the Replication
srcpath = conf["Replication"]["src_path"]
dstpath = conf["Replication"]["dst_path"]

# Save the configuration
with open('/root/.config/rclone/rclone.conf', 'w') as configfile:
    conf.write(configfile)

# Replicate the data from the sftp source to the S3 destination
subprocess.run(["/usr/bin/rclone", "copyto", "src-s3:" + srcpath, "dst-s3:" + dstpath, "-P", "--transfers", "16", "--checkers", "16"])
