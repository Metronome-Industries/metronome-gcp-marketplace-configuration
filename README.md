# Metronome GCP Marketplace Integration

> [!NOTE]
> This feature is coming soon! To get notified as soon as our GCP Marketplace integration is ready, reach out to your Metronome Representative.

This repository offers several configuration methods for deploying the necessary Google Cloud Platform (GCP) infrastructure to enable Metronome to meter usage for GCP Marketplace listings. It creates a Workload Identity Federation (WIF) configuration that allows Metronome's AWS-based metering service to securely access your GCP project and report usage data.

## Features

- **Workload Identity Federation**: Secure cross-cloud authentication between AWS and GCP
- **Service Account Management**: Creates and configures a dedicated service account for Metronome
- **Configuration Export**: Generates WIF configuration file for Metronome integration

## Architecture

This repository creates the following GCP resources:

1. **Workload Identity Pool**: Enables federation with AWS
2. **Workload Identity Pool Provider**: Configures AWS as an identity provider
3. **Service Account**: Dedicated account for Metronome metering operations

## Prerequisites

- GCP Project with billing enabled
- GCP Marketplace integration configured
- `gcloud` command line utility
- [For Terraform setup] Terraform >= 1.3.0

## Setup Options

You can set up the Metronome GCP Marketplace integration using any of these methods:

1. **Terraform**: Use the module in the [Terraform directory](./terraform) for automated infrastructure management
2. **Bash Script**: Use the provided [setup-gcp-marketplace-integration.sh](./setup-gcp-marketplace-integration.sh) script for automated `gcloud` setup
3. **Manual Setup**: Use `gcloud` commands in [GCLOUD_SETUP.md](./GCLOUD_SETUP.md) for a guided, manual configuration

## Option 1: Terraform Setup

### Basic Usage

The module will run as-is standalone. You can copy the provided [terraform/terraform.tfvars.example](./terraform/terraform.tfvars.example) to a `terraform/terraform.tfvars` file, edit the variable values as needed, and run the standard `terraform init`, `terraform plan`, and `terraform apply` workflow from the `terraform/` directory.

Alternatively, you can incorporate this into your existing Terraform configuration using a module declaration like the below:

```hcl
module "metronome_gcp_marketplace_metering" {
  source = "./path/to/metronome-gcp-marketplace-integration/terraform"

  # Required: Set the GCP project ID and project number where these resources should be deployed.
  # See https://cloud.google.com/resource-manager/docs/creating-managing-projects#identifying_projects
  # for where to look up your project ID and number.
  project_id                   = "your-gcp-project-id"
  project_number               = "your-gcp-project-number"

  # Required: Set Metronome-provided identifiers
  # See https://docs.metronome.com/integrations/marketplace-integrations/gcp
  # for where to look up these values in Metronome
  metronome_service_account_id = "your-metronome-service-account-id"
  metronome_aws_account_id     = "metronome-aws-account-id"
  metronome_aws_role_name      = "MetronomeAWSRoleName"

  # Optional: Customize naming
  # identifier_prefix   = "our-naming-convention"
  # display_name_prefix = "Our Naming Convention"
}
```

### Inputs

The Terraform module accepts the following inputs. You will need to supply identifiers from your GCP project as well as identifiers from Metronome.

**GCP Project Identifiers**: See [GCP Documentation](https://cloud.google.com/resource-manager/docs/creating-managing-projects#identifying_projects) for where to look up your project ID and number.
**Metronome Identifiers**: See [Metronome Documentation](https://docs.metronome.com/integrations/marketplace-integrations/gcp) for where to look up the Metronome-provided identifiers.

| Name                         | Description                                   | Type     | Default                       | Required |
| ---------------------------- | --------------------------------------------- | -------- | ----------------------------- | :------: |
| project_id                   | GCP project ID                                | `string` | n/a                           |   yes    |
| project_number               | GCP project number                            | `string` | n/a                           |   yes    |
| metronome_service_account_id | Metronome service account ID                  | `string` | n/a                           |   yes    |
| metronome_aws_account_id     | Metronome AWS account ID                      | `string` | n/a                           |   yes    |
| metronome_aws_role_name      | Metronome AWS IAM role name                   | `string` | n/a                           |   yes    |
| identifier_prefix            | Standard prefix to apply to any identifiers   | `string` | `"metronome-metering-prod"`   |    no    |
| display_name_prefix          | Standard prefix to apply to any display names | `string` | `"Metronome Metering (prod)"` |    no    |

### Outputs

| Name                        | Description                                          |
| --------------------------- | ---------------------------------------------------- |
| workload_identity_pool_id   | The ID of the created Workload Identity Pool         |
| workload_identity_pool_name | The name of the created Workload Identity Pool       |
| service_account_email       | Email address of the created service account         |
| retrieve_wif_config_cmd     | Generated command to retrieve WIF configuration file |

### Post-Deploy Step

After running this module, you'll need to:

1. **Retrieve the WIF configuration file** by running the command output by the module's `retrieve_wif_config_cmd` output
2. **Provide this file to Metronome** for Metronome's configuration

**Example**:

```bash
Apply complete! Resources: 7 added, 0 changed, 0 destroyed.

Outputs:

retrieve_wif_config_cmd = <<EOT
gcloud config set project example-project-id;
gcloud iam workload-identity-pools create-cred-config \
  projects/example-project-number/locations/global/workloadIdentityPools/metronome-metering-prod-pool/providers/metronome-metering-prod-provider \
  --service-account=metronome-metering-prod-sa@example-project-id.iam.gserviceaccount.com \
  --aws \
  --output-file=metronome-wif-config.json

EOT
```

Copying the command from the output and executing it should generate the appropriate credentials file in your current directory, which you will then submit to Metronome.

## Option 2: Automated Script Setup

The `setup-gcp-marketplace-integration.sh` script can be executed to automatically set up the necessary GCP resources for Metronome marketplace integration.

**[GCloud Setup Guide](GCLOUD_SETUP.md)** - Follow `Option A` in the guide to execute the script.

The script executes equivalent `gcloud` commands for all the resources created by this Terraform module.

## Option 3: Manual Setup with `gcloud` CLI

If you prefer to run each command individually and have full control over the process, you can set up the same infrastructure manually using `gcloud` commands.

**[GCloud Setup Guide](GCLOUD_SETUP.md)** - Follow `Option B` in the guide for step-by-step instructions using `gcloud` CLI

The manual setup guide provides equivalent `gcloud` commands for all the resources created by this Terraform module, with detailed explanations for each step.

## Permissions

This module creates a service account with the following permissions:

- **Workload Identity User**: Allows AWS principals to impersonate the service account
- **Service Management Service Controller**: Enables reporting usage to GCP Marketplace
- **Consumer Procurement Entitlement Viewer**: Read access to marketplace entitlements
