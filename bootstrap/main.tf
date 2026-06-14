terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    bucket         = "helmcove-tf-state-backend"
    key            = "bootstrap/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "helmcove-tf-state-locks"
    kms_key_id     = "arn:aws:kms:us-west-2:670523234679:key/6d626b57-ff5c-4122-985e-a91b29f25cef"
  }
}

#Adding aws as my provider, access key and secret is applied using "aws configure" cli
provider "aws" {
  region = "us-west-2"
}

#Create KMS to manage keys rotations and encryption 
resource "aws_kms_key" "tf_state_key" {
  description             = "KMS Key for encrypting Terraform remote state"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

# Create an alias for KSM key or else it would look like 1231vfeg-1243124
resource "aws_kms_alias" "tf_state_key_alias" {
  name          = "alias/helmcove-tf-state-key"
  target_key_id = aws_kms_key.tf_state_key.key_id
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "tf_state" {
  bucket        = "helmcove-tf-state-backend"
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

# Enable versioning so we can recover from accidental state corruption
resource "aws_s3_bucket_versioning" "tf_state_versioning" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enforce server side encryption through KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state_encrypt" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.tf_state_key.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# Block All Public Access 
resource "aws_s3_bucket_public_access_block" "tf_state_acl_block" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB Set up
resource "aws_dynamodb_table" "tf_locks" {
  name         = "helmcove-tf-state-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# Establish trust with GitHub and idp
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# Strict Trust Policy allowing only my specific repository to use this role
data "aws_iam_policy_document" "github_oidc_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Scopes to only my specific GitHub
      values = ["repo:Rookid21/aws-secure-ci-cd-gitops:*"]
    }
  }
}

# The IAM Role GitHub Actions will use to deploy any resources 
resource "aws_iam_role" "github_actions_role" {
  name               = "github-actions-infrastructure-role"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_trust.json
}

resource "aws_iam_role_policy" "github_actions_s3_backend_policy" {
  name = "github-actions-s3-backend-policy"
  role = aws_iam_role.github_actions_role.id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "S3BackendAndStateInspection",
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket",
          "s3:GetBucketPolicy",
          "s3:GetBucketAcl",
          "s3:GetBucketCORS",
          "s3:GetBucketWebsite",
          "s3:GetObject"
        ],
        "Resource" : [
          "arn:aws:s3:::helmcove-tf-state-backend",
          "arn:aws:s3:::helmcove-tf-state-backend/*"
        ]
      },
      {
        "Sid" : "KMSStateDecryptionAndInspection",
        "Effect" : "Allow",
        "Action" : [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:ListResourceTags"
        ],
        "Resource" : "arn:aws:kms:us-west-2:670523234679:key/6d626b57-ff5c-4122-985e-a91b29f25cef"
      },
      {
        "Sid" : "DynamoDBLockTableOperations",
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:ListTagsOfResource"
        ],
        "Resource" : "arn:aws:dynamodb:us-west-2:670523234679:table/helmcove-tf-state-locks"
      },
      {
        "Sid" : "IAMInfrastructureSelfInspection",
        "Effect" : "Allow",
        "Action" : [
          "iam:GetOpenIDConnectProvider",
          "iam:GetRole"
        ],
        "Resource" : [
          "arn:aws:iam::670523234679:oidc-provider/token.actions.githubusercontent.com",
          "arn:aws:iam::670523234679:role/github-actions-infrastructure-role",
          "arn:aws:iam::670523234679:role/github-actions-infrastructure-role*"
        ]
      }
    ]
  })
}

#Debugging Stuff
output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_role.arn
  description = "Provide this ARN to your GitHub Actions workflow configuration"
}

output "kms_key_arn" {
  value       = aws_kms_key.tf_state_key.arn
  description = "The ARN of the Customer Managed KMS Key encrypting the state bucket"
}