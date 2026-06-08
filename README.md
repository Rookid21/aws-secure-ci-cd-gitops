# Secure AWS GitOps CI/CD Pipeline 

[![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![GitHub Actions](https://img.shields.io/badge/github%20actions-%232088FF.svg?style=for-the-badge&logo=github-actions&logoColor=white)](https://github.com/features/actions)
[![Security-Standard](https://img.shields.io/badge/IAM-Zero%20Trust%20OIDC-red?style=for-the-badge)](https://aws.amazon.com/iam/)


### The Cloud Architecture
The project is to achieve a centralized state management utilizing AWS over local machines, providing strong encryption, collaboration, and security through IAM, KSM, and no local keys. 


AWS Initial Infrastructure Setup

## Terraform AWS Implementation Deep Dive 

### 🔑 AWS KMS
- Deploys an isolated KMS key resource giving access to data.
- Provides server side encryption across S3 backend, utilizing a 30 day key rotation, and provides better security then the regular AES256 encryption at rest. Beneifts like key rotation, aduiting, and access controls. 


### 🪣 AWS S3 Bucket 
- Created a helmcove-tf-state-backend bucket specifically for terraform.tf state files
- Enable version control for backups and resolving any potential corruption errors 
- S3 bucket ACL preventing public access
- Bucket-Key to cache KMS data keys saving costs


### 🆔 AWS IAM
- OIDC identity, not more AWS Acess Keys or Secret Keys inside code
- Restricts only to my repo `repo:Rookid21/aws-infra-bootstrap:*`


### GitOps Pipeline





- tfstate file in S3 Bucket
![alt text](image.png)

- Secure through KMS
![alt text](image-1.png)

- IAM role
![alt text](image-2.png)

- DynamoDB to avoid overlap corruption 
![alt text](image-3.png)