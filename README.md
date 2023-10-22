# Steps

## Setup

1. Signup for an Azure Subscription
2. Create the Service Principal for use with Terraform
3. Add the SP as a contributor to the subscription
4. update the template env.ps1 file with ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET and run
4. Download terraform and configure the binary into the PATH variable
5. `cd infra` and then run `terraform init`
6. run `terraform validate`
7. run `terraform plan`

