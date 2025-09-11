#!/bin/bash

# Metronome GCP Marketplace Integration Setup Script
# This script automates the manual gcloud setup process for Metronome GCP Marketplace integration
# See GCLOUD_SETUP.md for usage instructions

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to validate environment variables
validate_env_vars() {
  log_info "Validating required environment variables..."

  local missing_vars=()

  # Required variables
  if [[ -z "${GCP_PROJECT_ID:-}" ]]; then
    missing_vars+=("GCP_PROJECT_ID")
  fi

  if [[ -z "${GCP_PROJECT_NUMBER:-}" ]]; then
    missing_vars+=("GCP_PROJECT_NUMBER")
  fi

  if [[ -z "${METRONOME_AWS_ACCOUNT_ID:-}" ]]; then
    missing_vars+=("METRONOME_AWS_ACCOUNT_ID")
  fi

  if [[ -z "${METRONOME_AWS_ROLE_NAME:-}" ]]; then
    missing_vars+=("METRONOME_AWS_ROLE_NAME")
  fi

  if [[ -z "${METRONOME_SERVICE_ACCOUNT_ID:-}" ]]; then
    missing_vars+=("METRONOME_SERVICE_ACCOUNT_ID")
  fi

  if [[ ${#missing_vars[@]} -gt 0 ]]; then
    log_error "Missing required environment variables:"
    for var in "${missing_vars[@]}"; do
      echo "  - $var"
    done
    echo
    log_error "Please set all required environment variables before running this script."
    log_error "See GCLOUD_SETUP.md for detailed instructions."
    exit 1
  fi

  # Set optional variables with defaults
  export GCP_IDENTIFIER_PREFIX="${GCP_IDENTIFIER_PREFIX:-metronome-metering-prod}"
  export GCP_DISPLAY_NAME_PREFIX="${GCP_DISPLAY_NAME_PREFIX:-Metronome Metering (prod)}"

  log_success "All required environment variables are set"

  # Display configuration
  echo
  log_info "Configuration:"
  echo "  GCP Project ID: $GCP_PROJECT_ID"
  echo "  GCP Project Number: $GCP_PROJECT_NUMBER"
  echo "  Metronome AWS Account ID: $METRONOME_AWS_ACCOUNT_ID"
  echo "  Metronome AWS Role Name: $METRONOME_AWS_ROLE_NAME"
  echo "  Metronome Service Account ID: $METRONOME_SERVICE_ACCOUNT_ID"
  echo "  GCP Identifier Prefix: $GCP_IDENTIFIER_PREFIX"
  echo "  GCP Display Name Prefix: $GCP_DISPLAY_NAME_PREFIX"
  echo
}

# Function to check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."

  # Check if gcloud is installed
  if ! command_exists gcloud; then
    log_error "gcloud CLI is not installed or not in PATH"
    log_error "Please install gcloud CLI: https://cloud.google.com/sdk/docs/install"
    exit 1
  fi

  # Check if gcloud is authenticated
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
    log_error "gcloud is not authenticated"
    log_error "Please run: gcloud auth login"
    exit 1
  fi

  log_success "Prerequisites check passed"
}

# Function to configure gcloud project
configure_gcloud() {
  log_info "Configuring gcloud project..."

  if ! gcloud config set project "$GCP_PROJECT_ID"; then
    log_error "Failed to set gcloud project to $GCP_PROJECT_ID"
    exit 1
  fi

  log_success "gcloud configured for project: $GCP_PROJECT_ID"
}

# Function to create workload identity pool
create_workload_identity_pool() {
  log_info "Creating Workload Identity Pool..."

  if ! gcloud iam workload-identity-pools create "${GCP_IDENTIFIER_PREFIX}-pool" \
    --location="global" \
    --display-name="${GCP_DISPLAY_NAME_PREFIX} Pool" \
    --description="Identity pool for Metronome GCP Marketplace usage metering" \
    --mode="FEDERATION_ONLY"; then
    log_error "Failed to create Workload Identity Pool"
    exit 1
  fi

  log_success "Workload Identity Pool created: ${GCP_IDENTIFIER_PREFIX}-pool"
}

# Function to create workload identity pool provider
create_workload_identity_provider() {
  log_info "Creating Workload Identity Pool Provider..."

  if ! gcloud iam workload-identity-pools providers create-aws "${GCP_IDENTIFIER_PREFIX}-provider" \
    --location="global" \
    --workload-identity-pool="${GCP_IDENTIFIER_PREFIX}-pool" \
    --account-id="$METRONOME_AWS_ACCOUNT_ID" \
    --display-name="${GCP_DISPLAY_NAME_PREFIX} AWS" \
    --description="Allow Metronome Metering Lambda to impersonate service account" \
    --attribute-mapping="google.subject=assertion.arn.extract('assumed-role/{role}/'),attribute.account=assertion.account,attribute.aws_role=assertion.arn.extract('assumed-role/{role}/'),attribute.session_name=assertion.arn.extract('assumed-role/{role_and_session}').extract('/{session}')" \
    --attribute-condition="attribute.aws_role == '${METRONOME_AWS_ROLE_NAME}'"; then
    log_error "Failed to create Workload Identity Pool Provider"
    exit 1
  fi

  log_success "Workload Identity Pool Provider created: ${GCP_IDENTIFIER_PREFIX}-provider"
}

# Function to create service account
create_service_account() {
  log_info "Creating Service Account..."

  if ! gcloud iam service-accounts create "${METRONOME_SERVICE_ACCOUNT_ID}" \
    --display-name="${GCP_DISPLAY_NAME_PREFIX} Service Account" \
    --description="Service account to permit Metronome to meter GCP Marketplace usage"; then
    log_error "Failed to create Service Account"
    exit 1
  fi

  log_success "Service Account created: ${METRONOME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
}

# Function to grant IAM permissions
grant_iam_permissions() {
  log_info "Granting IAM permissions..."

  # Allow WIF principal to impersonate the service account
  log_info "Granting workloadIdentityUser role..."
  if ! gcloud iam service-accounts add-iam-policy-binding \
    "${METRONOME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${GCP_IDENTIFIER_PREFIX}-pool/attribute.account/${METRONOME_AWS_ACCOUNT_ID}"; then
    log_error "Failed to grant workloadIdentityUser role"
    exit 1
  fi

  # Grant service usage reporting permissions
  log_info "Granting serviceController role..."
  if ! gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
    --role="roles/servicemanagement.serviceController" \
    --member="serviceAccount:${METRONOME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"; then
    log_error "Failed to grant serviceController role"
    exit 1
  fi

  # Grant entitlement viewer permissions
  log_info "Granting entitlementViewer role..."
  if ! gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
    --role="roles/consumerprocurement.entitlementViewer" \
    --member="serviceAccount:${METRONOME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"; then
    log_error "Failed to grant entitlementViewer role"
    exit 1
  fi

  log_success "All IAM permissions granted"
}

# Function to generate WIF configuration file
generate_wif_config() {
  log_info "Generating WIF configuration file..."

  if ! gcloud iam workload-identity-pools create-cred-config \
    "projects/${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${GCP_IDENTIFIER_PREFIX}-pool/providers/${GCP_IDENTIFIER_PREFIX}-provider" \
    --service-account="${METRONOME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
    --aws \
    --output-file="metronome-wif-config.json"; then
    log_error "Failed to generate WIF configuration file"
    exit 1
  fi

  log_success "WIF configuration file generated: metronome-wif-config.json"
}

# Function to verify setup
verify_setup() {
  log_info "Verifying setup..."

  # Check if WIF config file exists
  if [[ ! -f "metronome-wif-config.json" ]]; then
    log_warning "WIF configuration file not found"
    return 1
  fi

  # Verify Workload Identity Pool
  if ! gcloud iam workload-identity-pools describe "${GCP_IDENTIFIER_PREFIX}-pool" --location="global" >/dev/null 2>&1; then
    log_warning "Workload Identity Pool verification failed"
    return 1
  fi

  # Verify Service Account
  if ! gcloud iam service-accounts describe "${METRONOME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" >/dev/null 2>&1; then
    log_warning "Service Account verification failed"
    return 1
  fi

  log_success "Setup verification completed successfully"
  return 0
}

# Main function
main() {
  echo "=============================================="
  echo "Metronome GCP Marketplace Integration Setup"
  echo "=============================================="
  echo

  validate_env_vars
  check_prerequisites
  configure_gcloud
  create_workload_identity_pool
  create_workload_identity_provider
  create_service_account
  grant_iam_permissions
  generate_wif_config

  if verify_setup; then
    echo
    echo "=============================================="
    log_success "Setup completed successfully!"
    echo "=============================================="
    echo
    log_info "Next steps:"
    echo "1. Provide the generated 'metronome-wif-config.json' file to Metronome"
    echo
    log_info "The WIF configuration file has been saved to: $(pwd)/metronome-wif-config.json"
  else
    echo
    echo "=============================================="
    log_warning "Setup completed with warnings"
    echo "=============================================="
    echo
    log_warning "Please verify the setup manually using the verification commands in GCLOUD_SETUP.md"
  fi
}

# Run main function
main "$@"
