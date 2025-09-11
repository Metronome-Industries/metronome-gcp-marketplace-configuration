/**
 * Metronome GCP Marketplace Integration Module
 *
 * See the root README.md file for more information on how to use this module.
 *
 * This module creates the necessary GCP resources for Metronome to meter usage
 * in GCP Marketplace integrations:
 * - Workload Identity Federation pool and provider for AWS-to-GCP authentication
 * - Service account following Metronome's required naming conventioin
 * - IAM bindings to allow Metronome's AWS role to impersonate the service account
 *
 * The module will run as-is standalone. You can copy the provided terraform.tfvars.example
 * to a terraform.tfvars file, edit the variable values as needed, and run the standard
 * terraform init, terraform plan, and terraform apply workflow.
 *
 * Alternatively, you can incorporate this into your existing Terraform configuration
 * using a module declaration like the below:
 *
 * module "metronome_gcp_marketplace_metering" {
 *   source = "./path/to/metronome-gcp-marketplace-integration"
 *
 *   project_id                   = "your-gcp-project-id"
 *   project_number               = "your-gcp-project-number"
 *   metronome_service_account_id = "your-metronome-service-account-id"
 *   metronome_aws_account_id     = "metronome-aws-account-id"
 *   metronome_aws_role_name      = "MetronomeAWSRoleName"
 *
 *   # Optional: Customize naming
 *   # identifier_prefix   = "our-naming-convention"
 *   # display_name_prefix = "Our Naming Convention"
 * }
 */

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0"
    }
  }
}

locals {
  wif_principal = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.metering_wif_pool.name}/attribute.account/${var.metronome_aws_account_id}"
}

resource "google_iam_workload_identity_pool" "metering_wif_pool" {
  provider = google-beta
  project  = var.project_number

  workload_identity_pool_id = "${var.identifier_prefix}-pool"
  display_name              = "${var.display_name_prefix} Pool"
  description               = "Identity pool for Metronome GCP Marketplace usage metering"
  mode                      = "FEDERATION_ONLY"

  disabled = false
}

resource "google_iam_workload_identity_pool_provider" "metering_wif_aws_provider" {
  provider = google-beta
  project  = var.project_number

  workload_identity_pool_id          = google_iam_workload_identity_pool.metering_wif_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.identifier_prefix}-provider"
  display_name                       = "${var.display_name_prefix} AWS"
  description                        = "Allow Metronome Metering Lambda to impersonate service account"

  disabled = false

  # For AWS-specific attribute mapping information, see:
  # https://cloud.google.com/iam/docs/workload-identity-federation-with-other-clouds#mappings-and-conditions
  attribute_mapping = {
    # google.subject must be unique and less than 127 characters. We extract the role name from the
    # assumed role ARN to ensure the value stays underneath the character limit.
    "google.subject"         = "assertion.arn.extract('assumed-role/{role}/')"
    "attribute.account"      = "assertion.account"
    "attribute.aws_role"     = "assertion.arn.extract('assumed-role/{role}/')"
    "attribute.session_name" = "assertion.arn.extract('assumed-role/{role_and_session}').extract('/{session}')"
  }
  attribute_condition = "attribute.aws_role == '${var.metronome_aws_role_name}'"

  aws {
    account_id = var.metronome_aws_account_id
  }
}

# Service Account controlling Metronome's permissions to meter GCP Marketplace listings
resource "google_service_account" "metering_service_account" {
  account_id   = var.metronome_service_account_id
  display_name = "${var.display_name_prefix} Service Account"
  description  = "Service account to permit Metronome to meter GCP Marketplace usage"
  project      = var.project_id
}

# Allow WIF principal to impersonate the Service Account
resource "google_service_account_iam_member" "allow_wif_impersonation" {
  service_account_id = google_service_account.metering_service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.wif_principal
}
