### Required configuration ###

variable "project_id" {
  description = "GCP project ID. See https://cloud.google.com/resource-manager/docs/creating-managing-projects#identifying_projects for where to look up your project ID."
  type        = string
}

variable "project_number" {
  description = "GCP project number. See https://cloud.google.com/resource-manager/docs/creating-managing-projects#identifying_projects for where to look up your project number."
  type        = string
}

variable "metronome_service_account_id" {
  description = "Service account ID provided by Metronome, returned to you in Metronome UI during GCP Marketplace integration setup. This value will be used as the ID of the GCP service account."
  type        = string
}

variable "metronome_aws_account_id" {
  description = "Metronome's AWS account ID that will be granted access to your GCP resources via Workload Identity Federation. This value is provided by Metronome during GCP Marketplace integration setup."
  type        = string
}

variable "metronome_aws_role_name" {
  description = "Name of the AWS IAM role that Metronome will assume to access your GCP resources. This value is provided by Metronome during GCP Marketplace integration setup."
  type        = string
}

### Optional configuration ###

variable "identifier_prefix" {
  description = "Standard prefix to apply to any identifiers. We recommend using an environment-specific identifier in the prefix in case you want to deploy this integration to multiple logical environments. The service account we generate will not follow this convention -- it must exactly match the metronome_service_account_id."
  type        = string
  default     = "metronome-metering-prod"

  validation {
    condition     = length("${var.identifier_prefix}-provider") <= 63
    error_message = "The length of the longest identifier may not exceed 63 characters. Please use a shorter identifier prefix (current length: ${length("${var.identifier_prefix}")})."
  }
}

variable "display_name_prefix" {
  description = "Standard prefix to apply to any display names. We recommend using an environment-specific identifier in the prefix in case you want to deploy this integration to multiple logical environments"
  type        = string
  default     = "Metronome Metering (prod)"

  validation {
    condition     = length("${var.display_name_prefix} AWS") <= 32
    error_message = "The length of the longest display name may not exceed 32 characters. Please use a shorter display name prefix (current length: ${length("${var.display_name_prefix}")})."
  }
}
