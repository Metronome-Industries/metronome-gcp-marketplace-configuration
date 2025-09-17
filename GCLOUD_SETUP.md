# Setup Guide - GCP Marketplace Metronome Integration

This guide provides step-by-step instructions to manually set up the GCP infrastructure for Metronome marketplace integration using `gcloud` commands instead of Terraform.

## Prerequisites

- GCP Project with billing enabled
- GCP Marketplace integration configured
- `gcloud` CLI installed and authenticated
- Project Owner or IAM Admin permissions

## Overview

In order for Metronome to manage usage reporting on behalf of your GCP Marketplace listing, we need to grant Metronome's metering service access to your GCP project. This is achieved through Workload Identity Federation (WIF), which allows us to securely authenticate Metronome's AWS-based metering service to access your GCP resources and grant it only the access it needs to perform metering.

The following steps will guide you through creating:

- A Workload Identity Pool for AWS-GCP federation
- A Workload Identity Pool Provider for AWS
- A Service Account that identifies our metering service in your GCP project

At the end of the configuration, you will have generated a Workload Identity Federation configuration file (`metronome-wif-config.json`) that you will provide to Metronome to complete the integration setup.

## Setup Instructions -- Configure local environment

### 1. Set Environment Variables

First, in a new terminal window, set up your environment variables. The following commands throughout this document need to be run from the same terminal session, as we will be leveraging environment variables for any identifiers.

#### Required: Set GCP Identifiers and Configure `gcloud`

Set the GCP project ID and project number where these resources should be deployed. See the [GCP Documentation](https://cloud.google.com/resource-manager/docs/creating-managing-projects#identifying_projects) for where to look up your project ID and number. Use `gcloud config` to point it at the desired project as well.

```bash
export GCP_PROJECT_ID="your-gcp-project-id"
export GCP_PROJECT_NUMBER="9999999999999"

gcloud config set project $GCP_PROJECT_ID
```

#### Required: Set Metronome-provided Identifiers

Metronome will be accessing GCP APIs on your behalf to report usage. Metronome's AWS Account therefore needs to be granted access to the appropriate APIs via WIF + Service Account configuration. The following identifiers are provided by Metronome via the GCP Marketplace integration setup and will need to be set as environment variables (refer to [Metronome Documentation](https://docs.metronome.com/integrations/marketplace-integrations/gcp) for more information about setting these values):

```bash
# Get these values from Metronome
export METRONOME_AWS_ACCOUNT_ID="metronome-aws-account-id"
export METRONOME_AWS_ROLE_NAME="MetronomeAWSRoleName"
export METRONOME_SERVICE_ACCOUNT_ID="your-metronome-service-account-id"
```

#### Optional: Customize Naming

The GCP identifiers and display names will follow a default naming convention, but you can customize this to better align with your organization's naming conventions if you wish.

By default, we will create resources in GCP with the following naming convention:

```bash
metronome-metering-prod-pool
metronome-metering-prod-provider
metronome-metering-prod-sa
```

You can override or customize this by setting the following environment variables. We recommend using an environment-specific identifier in the prefix in case you want to deploy this integration to multiple logical environments, each with their own pool + service account.

```bash
# Standardized prefix for generated identifiers in GCP
export GCP_IDENTIFIER_PREFIX="metronome-metering-prod"
# Standardized prefix for any display names in Google Console
export GCP_DISPLAY_NAME_PREFIX="Metronome Metering (prod)"
```

Note that GCP identifiers (e.g. `metronome-metering-prod-pool`) are limited to 63 characters, while display names (e.g. `Metronome Metering (prod) Pool`) are limited to 32 characters.

### 2. Enable Required APIs

Enable the necessary GCP APIs, if they are not already enabled, in order to create the necessary IAM + WIF resources:

```bash
gcloud services enable iam.googleapis.com
gcloud services enable iamcredentials.googleapis.com
gcloud services enable sts.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
```

You'll additionally need the following APIs enabled for the Marketplace Integration, although these should be enabled already in order for your listing to be published:

```bash
gcloud services enable cloudcommerceconsumerprocurement.googleapis.com
gcloud services enable serviceusage.googleapis.com
```

## Setup Instructions -- Option A: Execute script

We've included a Bash script that executes all the necessary `gcloud` commands automatically:

```bash
./setup-gcp-marketplace-integration.sh
```

The script will generate `metronome-wif-config.json` in the current directory.

## Setup Instructions -- Option B: Execute commands manually

If preferred, you can execute the `gcloud` commands manually. The following steps are the same as those executed by the script.

### 1. Create Workload Identity Pool

Create the Workload Identity Pool for AWS-GCP federation:

```bash
gcloud iam workload-identity-pools create "${GCP_IDENTIFIER_PREFIX}-pool" \
    --location="global" \
    --display-name="${GCP_DISPLAY_NAME_PREFIX} Pool" \
    --description="Identity pool for Metronome GCP Marketplace usage metering" \
    --mode="FEDERATION_ONLY"
```

### 2. Create Workload Identity Pool Provider

Create the AWS provider for the Workload Identity Pool:

```bash
gcloud iam workload-identity-pools providers create-aws "${GCP_IDENTIFIER_PREFIX}-provider" \
    --location="global" \
    --workload-identity-pool="${GCP_IDENTIFIER_PREFIX}-pool" \
    --account-id="$METRONOME_AWS_ACCOUNT_ID" \
    --display-name="${GCP_DISPLAY_NAME_PREFIX} AWS" \
    --description="Allow Metronome Metering Lambda to impersonate service account" \
    --attribute-mapping="google.subject=assertion.arn.extract('assumed-role/{role}/'),attribute.account=assertion.account,attribute.aws_role=assertion.arn.extract('assumed-role/{role}/'),attribute.session_name=assertion.arn.extract('assumed-role/{role_and_session}').extract('/{session}')" \
    --attribute-condition="attribute.aws_role == '${METRONOME_AWS_ROLE_NAME}'"
```

### 3. Create Service Account

Create the service account for Metronome operations:

```bash
gcloud iam service-accounts create "${METRONOME_SERVICE_ACCOUNT_ID}" \
    --display-name="${GCP_DISPLAY_NAME_PREFIX} Service Account" \
    --description="Service account to permit Metronome to meter GCP Marketplace usage"
```

### 4. Grant IAM Permissions

Grant the necessary permissions to the service account:

```bash
# Allow WIF principal to impersonate the service account
gcloud iam service-accounts add-iam-policy-binding \
    "${METRONOME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${GCP_IDENTIFIER_PREFIX}-pool/attribute.account/${METRONOME_AWS_ACCOUNT_ID}"
```

### 5. Generate WIF Configuration File

Create the Workload Identity Federation configuration file that Metronome will use:

```bash
gcloud iam workload-identity-pools create-cred-config \
  "projects/${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${GCP_IDENTIFIER_PREFIX}-pool/providers/${GCP_IDENTIFIER_PREFIX}-provider" \
  --service-account="${METRONOME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --aws \
  --output-file="metronome-wif-config.json"
```

## Verification

Verify that all resources were created successfully:

```bash
# Check Workload Identity Pool
gcloud iam workload-identity-pools describe "${GCP_IDENTIFIER_PREFIX}-pool" --location="global"

# Check Workload Identity Pool Provider
gcloud iam workload-identity-pools providers describe "${GCP_IDENTIFIER_PREFIX}-provider" \
    --location="global" --workload-identity-pool="${GCP_IDENTIFIER_PREFIX}-pool"

# Check Service Account
gcloud iam service-accounts describe "${METRONOME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Check permissions bound to the Service Account
gcloud projects get-iam-policy "${GCP_PROJECT_ID}" \
  --flatten="bindings[].members" \
  --format='table(bindings.role)' \
  --filter="bindings.members:${METRONOME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Check Service Account bound to the WIF principal
gcloud iam service-accounts get-iam-policy "${METRONOME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --flatten="bindings[].members" \
  --format='table(bindings.role, bindings.members)' \
  --filter="bindings.members:workloadIdentityPools"
```

## Next Steps

1. **Provide the WIF configuration file** (`metronome-wif-config.json`) to Metronome to complete the integration setup

## Cleanup

To remove all created resources, run the commands in reverse order:

```bash
# Remove WIF binding
gcloud iam service-accounts remove-iam-policy-binding \
    "${METRONOME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${GCP_IDENTIFIER_PREFIX}-pool/attribute.account/${METRONOME_AWS_ACCOUNT_ID}"

# Delete service account
gcloud iam service-accounts delete "${METRONOME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" --quiet

# Delete WIF provider
# Note that this will only soft-delete the provider. It will be purged after 30 days unless re-enabled.
# While in the soft-deleted state, it cannot be used to auth to the pool.
gcloud iam workload-identity-pools providers delete "${GCP_IDENTIFIER_PREFIX}-provider" \
    --location="global" --workload-identity-pool="${GCP_IDENTIFIER_PREFIX}-pool" --quiet

# Delete WIF pool
# Note that this will only soft-delete the pool. It will be purged after 30 days unless re-enabled.
# While in the soft-deleted state, it cannot be used to mint new tokens.
gcloud iam workload-identity-pools delete "${GCP_IDENTIFIER_PREFIX}-pool" --location="global" --quiet
```
