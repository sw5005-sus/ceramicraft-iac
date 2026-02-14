# ceramicraft-iac

This repository contains the Infrastructure as Code (IaC) for managing the Ceramicraft project. It uses Terraform and Ansible to provision and manage the infrastructure, including Kubernetes (k3s) clusters and CI/CD pipelines.

## Project Structure

| Directory           | Description                                              |
|---------------------|----------------------------------------------------------|
| `.github/workflow`  | CI/CD pipeline configuration                             |
| `k3s/main.tf`       | Terraform configuration for k3s node provisioning        |
| `k3s/ansible`       | Ansible playbooks for k3s environment setup and ArgoCD initialization |

## Prerequisites

### Backend Server Preparation

Before running Terraform, ensure the following backend resources are created in AWS:

1. **Create an S3 Bucket**:
   - This bucket will be used to store the Terraform state file.
   - Enable versioning on the bucket to maintain a history of state file changes.
   - Example AWS CLI commands:
     ```bash
     aws s3api create-bucket --bucket ceramicraft-terraform-state --region <your-region> --create-bucket-configuration LocationConstraint=<your-region>
     aws s3api put-bucket-versioning --bucket ceramicraft-terraform-state --versioning-configuration Status=Enabled
     ```

2. **Create a DynamoDB Table**:
   - This table will be used for state locking to prevent concurrent modifications to the Terraform state.
   - The table must have a primary key named `LockID` (of type `String`).
     ```bash
     aws dynamodb create-table \
         --table-name terraform-lock \
         --attribute-definitions AttributeName=LockID,AttributeType=S \
         --key-schema AttributeName=LockID,KeyType=HASH \
         --billing-mode PAY_PER_REQUEST
     ```

### GitHub Actions Preparation

To enable the CI/CD pipeline, configure the following secrets in your GitHub repository:

1. **AWS Access ID and Secret**:
   - Add `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` as secrets in your GitHub repository. These credentials should have sufficient permissions to manage the required AWS resources.

2. **SSH Key Setup**:
   - Add your private SSH key as a secret (e.g., `SSH_PRIVATE_KEY`) to allow GitHub Actions to connect to your servers.

3. **Secrets File Setup**:
   - Add any additional secrets required for your project (e.g., database credentials, API keys) as GitHub repository secrets.

---

## Manual Operation Steps

To manually deploy the infrastructure, follow these steps:

1. **Initialize Terraform**:
   Run the following command to initialize the Terraform working directory:
   ```bash
   terraform init
   ```
2. **Plan the Infrastructure**:
    Preview the changes Terraform will make:
    ```bash
   terraform plan
   ```
3. **Apply the Changes**:
    Apply the changes to provision the infrastructure:
    ```bash
   terraform apply
   ```
---
## Additional Notes
* Ensure that your AWS credentials are properly configured and have the necessary permissions to create and manage resources such as S3 buckets, DynamoDB tables, and EC2 instances.
* The `k3s/ansible` directory contains playbooks for setting up the k3s environment and initializing ArgoCD. Refer to the playbooks for further details on their usage.
* The CI/CD pipeline in `.github/workflow` automates the deployment process. Ensure all required GitHub secrets are configured before running the pipeline.

---
## Support
If you encounter any issues or have questions, please open an issue in this repository or contact the project maintainers.