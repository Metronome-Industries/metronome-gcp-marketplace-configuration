output "workload_identity_pool_id" {
  description = "The ID of the created Workload Identity Pool"
  value       = google_iam_workload_identity_pool.metering_wif_pool.workload_identity_pool_id
}

output "workload_identity_pool_name" {
  description = "The name of the created Workload Identity Pool"
  value       = google_iam_workload_identity_pool.metering_wif_pool.name
}

output "service_account_email" {
  description = "Email address of the created service account"
  value       = google_service_account.metering_service_account.email
}

output "retrieve_wif_config_cmd" {
  value = <<-EOC

  # Run these commands to retrieve the WIF configuration file via gcloud:
  gcloud config set project ${var.project_id};
  gcloud iam workload-identity-pools create-cred-config \
    ${google_iam_workload_identity_pool_provider.metering_wif_aws_provider.name} \
    --service-account=${google_service_account.metering_service_account.email} \
    --aws \
    --output-file=metronome-wif-config.json

  # Alternatively, you may download the WIF config from the GCP Console:
  # 1. Navigate to https://console.cloud.google.com/iam-admin/workload-identity-pools/pool/${google_iam_workload_identity_pool.metering_wif_pool.workload_identity_pool_id}?inv=1&invt=Ab1EGg&project=${var.project_id}
  # 2. Click "Connected service accounts"
  # 3. Click the Download button next to '${google_service_account.metering_service_account.account_id}'
  EOC
}
