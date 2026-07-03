# Combined Terraform of main.tf, variables.tf, version.tf


########################################################
# Terraform Dependencies
########################################################

terraform {
  required_version = ">= 1.4.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.80.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 1.12.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}
  # Optional: let Terraform set a specific context subscription when needed.
  # Otherwise, azurerm will use Azure CLI default subscription or ARM_* env vars.
  subscription_id                 = var.context_subscription_id
  resource_provider_registrations = "none"
}

provider "azapi" {}

provider "azuread" {}



########################################################
# Variables
########################################################

variable "managing_tenant_id" {
  description = "AccuKnox tenant ID"
  type        = string
  default     = "3d64034d-3c3e-4959-b019-f15558be8a4e"
}

variable "accuknox_verification_token" {
  description = "Unique verification token provided by AccuKnox (DO NOT MODIFY)"
  type        = string
  default     = "AK-CNAPP-{{TOKEN}}"

  validation {
    condition     = can(regex("^AK-CNAPP-", var.accuknox_verification_token))
    error_message = "Verification token must start with 'AK-CNAPP-'"
  }
}



# User Provides
variable "management_group_id" {
  description = "Root management group ID where the policy will be assigned"
  type        = string
  default     = ""
}

variable "context_subscription_id" {
  description = "Subscription ID where the shared lighthouse definition will be created"
  type        = string
  default     = ""

  validation {
    condition     = var.context_subscription_id != null && var.context_subscription_id != ""
    error_message = "context_subscription_id must be provided"
  }
}



variable "offer_name" {
  description = "Lighthouse offer name"
  type        = string
  default     = "AccuKnox Delegation for CSPM Scanning"
}
variable "offer_description" {
  description = "Lighthouse offer description"
  type        = string
  default     = "Delegated read-only access via Lighthouse"
}



variable "authorizations" {
  description = "List of authorizations for Lighthouse"
  type = list(object({
    principal_id                  = string
    principal_display_name        = string
    role_definition_id            = string
    delegated_role_definition_ids = optional(list(string))
  }))
  default = [
    {
      principal_id           = "603f62f6-283e-4307-9735-d4a801daf8aa" # AccuKnox App Register
      principal_display_name = "AccuKnox CSPM Reader"
      role_definition_id     = "acdd72a7-3385-48ef-bd42-f606fba81ae7" # Reader
    },
    {
      principal_id           = "cc2d4923-7605-4505-82e2-5235216d03fc"
      principal_display_name = "Ayush Aggarwal"
      role_definition_id     = "acdd72a7-3385-48ef-bd42-f606fba81ae7"
    }
  ]
}



variable "mode" {
  description = "Onboarding mode: 'include' or 'exclude'"
  type        = string
  default     = "exclude"

  validation {
    condition     = contains(["include", "exclude"], var.mode)
    error_message = "mode must be 'include' or 'exclude'"
  }
}


# Global exclusions (applies to both modes)
variable "excluded_subscription_ids" {
  description = "Subscriptions to exclude globally"
  type        = list(string)
  default     = []
}


# Include mode variables (use when mode = "include")
variable "included_management_group_ids" {
  description = "Management groups to include (include mode only)"
  type        = list(string)
  default     = []
}

variable "include_extra_subscription_ids" {
  description = "Extra subscriptions to include outside of management groups (include mode only)"
  type        = list(string)
  default     = []
}


# Exclude mode variables (use when mode = "exclude")
variable "excluded_management_groups" {
  description = "Management groups to exclude (exclude mode only)"
  type        = list(string)
  default     = []
}

variable "include_exception_subscription_ids" {
  description = "Subscriptions to include even if their management group is excluded (exclude mode only)"
  type        = list(string)
  default     = []
}



variable "policy_definition_name" {
  description = "Custom policy definition name"
  type        = string
  default     = "Enable-Azure-Lighthouse-AccuKnox"
}

variable "policy_assignment_name" {
  description = "Policy assignment name"
  type        = string
  default     = "lh-enf"

  validation {
    condition     = length(var.policy_assignment_name) >= 1 && length(var.policy_assignment_name) <= 24
    error_message = "policy_assignment_name must be 1-24 characters"
  }
}

variable "policy_assignment_location" {
  description = "Azure region for policy assignment managed identity"
  type        = string
  default     = "eastus"
}

variable "deployment_location" {
  description = "Location for ARM template deployments"
  type        = string
  default     = "eastus"
}

# Variables related to policy management 

variable "root_tenant_id" {
  description = "Azure tenant ID for which policies need to be managed"
  type        = string
}

variable "accuknox_saas_client_id" {
  description = "Generate a saas client id using uuidgen command"
  type        = string
}

variable "policy_management_resource_group_location" {
  description = "Location of the resource group for policy management related resources"
  type        = string
  default     = "eastus"
}

variable "alerts_webhook_url" {
  description = "SaaS webhook URL to send azure alerts to"
  type        = string
}

variable "accuknox_saas_tenant_id" {
  description = "SaaS tenant id"
  type        = string
}


#############################################
# Data: Azure AD data source
#############################################

data "azuread_client_config" "current" {}


########################################################
# Data: Management Groups
########################################################

data "azurerm_management_group" "target" {
  name = var.management_group_id
}

data "azurerm_management_group" "included" {
  for_each = toset(local.filtered_included_management_group_ids)
  name     = each.value
}

########################################################
# Locals
########################################################

locals {
  mg_scope_id = data.azurerm_management_group.target.id

  # Transform authorizations to the format expected by azurerm_lighthouse_definition
  managed_by_authorizations = [
    for a in var.authorizations : merge(
      {
        principal_id           = a.principal_id
        principal_display_name = a.principal_display_name
        role_definition_id     = a.role_definition_id
      },
      length(coalesce(a.delegated_role_definition_ids, [])) > 0 ? {
        delegated_role_definition_ids = a.delegated_role_definition_ids
      } : {}
    )
  ]

  # Use context subscription for lighthouse definition
  customer_subscription_id = var.context_subscription_id
}

########################################################
# Data Sources for Subscription Discovery
########################################################

# Discover subscriptions per included management group using Resource Graph
data "external" "included_mg_subs" {
  for_each = toset(local.filtered_included_management_group_ids)
  program = ["bash", "-c", <<-EOT
    az graph query -q "ResourceContainers | where type == 'microsoft.resources/subscriptions' | extend mgChain = properties.managementGroupAncestorsChain | where mgChain has '${each.value}' | project subscriptionId" -o json | jq -c '{subscriptions: ([.data[].subscriptionId] | @json)}'
  EOT
  ]
}

# Discover descendants under the root MG (exclude mode, recursive)
data "azapi_resource_list" "root_mg_descendants" {
  count     = var.mode == "exclude" ? 1 : 0
  parent_id = local.mg_scope_id
  type      = "Microsoft.Management/managementGroups/descendants@2020-05-01"
}

# Discover descendants under excluded MGs (to subtract recursively)
data "azapi_resource_list" "excluded_mg_descendants" {
  for_each  = var.mode == "exclude" ? toset(var.excluded_management_groups) : []
  parent_id = "/providers/Microsoft.Management/managementGroups/${each.value}"
  type      = "Microsoft.Management/managementGroups/descendants@2020-05-01"
}

########################################################
# Subscription ID Collections
########################################################

locals {
  # Map: subscription ID -> included MG ID it belongs to
  include_sub_to_mg = var.mode == "include" ? merge(
    [
      for mg, res in data.external.included_mg_subs : {
        for sub_id in try(jsondecode(res.result.subscriptions), []) :
        sub_id => mg
      }
    ]...
  ) : {}

  # Subscriptions under included MGs, excluding explicitly excluded subs
  include_mode_subscription_ids = var.mode == "include" ? [
    for sub_id, mg in local.include_sub_to_mg : sub_id
    if !contains(coalesce(var.excluded_subscription_ids, []), sub_id)
  ] : []

  # Exclude mode: compute subscription IDs under root MG (recursive) and subtract excluded MGs (recursive)
  root_mg_subscription_ids = var.mode == "exclude" ? [
    for item in try(data.azapi_resource_list.root_mg_descendants[0].output.value, []) : item.name
    if lower(try(item.type, "")) == "microsoft.management/managementgroups/subscriptions"
  ] : []

  excluded_mg_subscription_ids = var.mode == "exclude" ? flatten([
    for mg, res in data.azapi_resource_list.excluded_mg_descendants : [
      for item in try(res.output.value, []) : item.name
      if lower(try(item.type, "")) == "microsoft.management/managementgroups/subscriptions"
    ]
  ]) : []

  # Subscriptions to onboard under exclude mode
  exclude_mode_subscription_ids = var.mode == "exclude" ? [
    for sub_id in local.root_mg_subscription_ids : sub_id
    if !contains(coalesce(var.excluded_subscription_ids, []), sub_id)
    && !contains(local.excluded_mg_subscription_ids, sub_id)
    && !contains(coalesce(var.include_exception_subscription_ids, []), sub_id)
  ] : []

  # Filter out empty subscription IDs from extra subscriptions
  filtered_include_extra_subscription_ids = var.mode == "include" ? [
    for sub_id in var.include_extra_subscription_ids : sub_id
    if sub_id != ""
  ] : []

  # Filter out empty subscription IDs from exception subscriptions
  filtered_include_exception_subscription_ids = var.mode == "exclude" ? [
    for sub_id in var.include_exception_subscription_ids : sub_id
    if sub_id != ""
  ] : []

  # Filter out empty management group IDs
  filtered_included_management_group_ids = var.mode == "include" ? [
    for mg_id in var.included_management_group_ids : mg_id
    if mg_id != ""
  ] : []

  # Final resolved list of ALL subscription IDs that should send logs
  # This combines all subscriptions from both include and exclude modes
  all_onboarded_subscription_ids = distinct(concat(
    local.include_mode_subscription_ids,
    local.filtered_include_extra_subscription_ids,
    local.exclude_mode_subscription_ids,
    local.filtered_include_exception_subscription_ids,
  ))
}

########################################################
# Shared Lighthouse Registration Definition
########################################################

resource "azurerm_lighthouse_definition" "shared_lighthouse_definition" {
  name               = "${var.offer_name} - ${var.accuknox_verification_token}"
  description        = var.offer_description
  managing_tenant_id = var.managing_tenant_id
  scope              = "/subscriptions/${local.customer_subscription_id}"

  dynamic "authorization" {
    for_each = var.authorizations
    content {
      principal_id                  = authorization.value.principal_id
      principal_display_name        = authorization.value.principal_display_name
      role_definition_id            = authorization.value.role_definition_id
      delegated_role_definition_ids = try(authorization.value.delegated_role_definition_ids, null)
    }
  }
}

########################################################
# Lighthouse Assignments for Target Subscriptions
########################################################

# Assignment for extra subscriptions (include mode)
resource "azurerm_lighthouse_assignment" "include_extra_subscriptions" {
  count                    = length(local.filtered_include_extra_subscription_ids)
  scope                    = "/subscriptions/${local.filtered_include_extra_subscription_ids[count.index]}"
  lighthouse_definition_id = azurerm_lighthouse_definition.shared_lighthouse_definition.id
}

# Assignment for subscriptions under included management groups
resource "azurerm_lighthouse_assignment" "included_mg_subscriptions" {
  for_each                 = var.mode == "include" ? toset(local.include_mode_subscription_ids) : []
  scope                    = "/subscriptions/${each.value}"
  lighthouse_definition_id = azurerm_lighthouse_definition.shared_lighthouse_definition.id
}

# Assignment for exclude mode subscriptions
resource "azurerm_lighthouse_assignment" "exclude_mode_subscriptions" {
  for_each                 = var.mode == "exclude" ? toset(local.exclude_mode_subscription_ids) : []
  scope                    = "/subscriptions/${each.value}"
  lighthouse_definition_id = azurerm_lighthouse_definition.shared_lighthouse_definition.id
}

# Assignment for exception subscriptions (exclude mode)
resource "azurerm_lighthouse_assignment" "exclude_mode_exceptions" {
  count                    = length(local.filtered_include_exception_subscription_ids)
  scope                    = "/subscriptions/${local.filtered_include_exception_subscription_ids[count.index]}"
  lighthouse_definition_id = azurerm_lighthouse_definition.shared_lighthouse_definition.id
}

########################################################
# Policy for Automatic Assignment to New Subscriptions
########################################################

# Simple policy that creates lighthouse assignments for new subscriptions
# Create policy definition at each included management group to ensure scope compatibility
resource "azurerm_policy_definition" "auto_lighthouse_assignment" {
  for_each            = var.mode == "include" ? toset(local.filtered_included_management_group_ids) : toset([var.management_group_id])
  name                = var.policy_definition_name
  management_group_id = "/providers/Microsoft.Management/managementGroups/${each.value}"
  policy_type         = "Custom"
  mode                = "All"
  display_name        = "Auto-assign AccuKnox Lighthouse to new subscriptions"
  description         = "Automatically creates lighthouse assignments for new subscriptions using the shared definition"

  parameters = jsonencode({
    lighthouseDefinitionId = {
      type         = "string"
      defaultValue = azurerm_lighthouse_definition.shared_lighthouse_definition.id
    }
  })

  policy_rule = jsonencode({
    if = {
      field  = "type"
      equals = "Microsoft.Resources/subscriptions"
    }
    then = {
      effect = "deployIfNotExists"
      details = {
        type              = "Microsoft.ManagedServices/registrationAssignments"
        deploymentScope   = "Subscription"
        existenceScope    = "Subscription"
        evaluationDelay   = "AfterProvisioning"
        roleDefinitionIds = ["/providers/Microsoft.Authorization/roleDefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635"] # Owner
        existenceCondition = {
          allOf = [
            {
              field  = "type"
              equals = "Microsoft.ManagedServices/registrationAssignments"
            },
            {
              field  = "Microsoft.ManagedServices/registrationAssignments/registrationDefinitionId"
              equals = "[parameters('lighthouseDefinitionId')]"
            }
          ]
        }
        deployment = {
          location = var.deployment_location
          properties = {
            mode = "incremental"
            parameters = {
              lighthouseDefinitionId = {
                value = "[parameters('lighthouseDefinitionId')]"
              }
            }
            template = {
              "$schema"      = "https://schema.management.azure.com/2018-05-01/subscriptionDeploymentTemplate.json#"
              contentVersion = "1.0.0.0"
              parameters = {
                lighthouseDefinitionId = { type = "string" }
              }
              variables = {
                assignmentName = "[guid(parameters('lighthouseDefinitionId'), subscription().subscriptionId)]"
              }
              resources = [
                {
                  type       = "Microsoft.ManagedServices/registrationAssignments"
                  apiVersion = "2020-02-01-preview"
                  name       = "[variables('assignmentName')]"
                  properties = {
                    registrationDefinitionId = "[parameters('lighthouseDefinitionId')]"
                  }
                }
              ]
            }
          }
        }
      }
    }
  })
}

########################################################
# Policy Assignments for Automatic Onboarding
########################################################

# Policy assignment for include mode
resource "azurerm_management_group_policy_assignment" "auto_lighthouse_include" {
  count                = length(local.filtered_included_management_group_ids)
  name                 = "${var.policy_assignment_name}-auto-${substr(local.filtered_included_management_group_ids[count.index], 0, 8)}"
  display_name         = "Auto Lighthouse Assignment - ${local.filtered_included_management_group_ids[count.index]}"
  management_group_id  = "/providers/Microsoft.Management/managementGroups/${local.filtered_included_management_group_ids[count.index]}"
  policy_definition_id = azurerm_policy_definition.auto_lighthouse_assignment[local.filtered_included_management_group_ids[count.index]].id
  location             = var.policy_assignment_location
  enforce              = true
  not_scopes           = [for sub in var.excluded_subscription_ids : "/subscriptions/${sub}"]

  identity { type = "SystemAssigned" }

  parameters = jsonencode({
    lighthouseDefinitionId = { value = azurerm_lighthouse_definition.shared_lighthouse_definition.id }
  })

  depends_on = [azurerm_lighthouse_definition.shared_lighthouse_definition]
}

resource "azurerm_role_assignment" "auto_policy_identity_owner_include" {
  count              = length(local.filtered_included_management_group_ids)
  scope              = "/providers/Microsoft.Management/managementGroups/${local.filtered_included_management_group_ids[count.index]}"
  role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635" # Owner
  principal_id       = azurerm_management_group_policy_assignment.auto_lighthouse_include[count.index].identity[0].principal_id
  principal_type     = "ServicePrincipal"
}

########################################################
# Automatic Remediation for Include Mode
########################################################

# Create remediation task for each management group
resource "azurerm_management_group_policy_remediation" "auto_lighthouse_include" {
  count                = length(local.filtered_included_management_group_ids)
  name                 = "remediate-lighthouse-${local.filtered_included_management_group_ids[count.index]}"
  management_group_id  = "/providers/Microsoft.Management/managementGroups/${local.filtered_included_management_group_ids[count.index]}"
  policy_assignment_id = azurerm_management_group_policy_assignment.auto_lighthouse_include[count.index].id
  location_filters     = []
  failure_percentage   = 1.0
  parallel_deployments = 10
  resource_count       = 500

  depends_on = [
    azurerm_role_assignment.auto_policy_identity_owner_include
  ]
}

# Policy assignment for exclude mode
resource "azurerm_management_group_policy_assignment" "auto_lighthouse_exclude" {
  count                = var.mode == "exclude" ? 1 : 0
  name                 = "${var.policy_assignment_name}-auto-exclude"
  display_name         = "Auto Lighthouse Assignment - Exclude Mode"
  management_group_id  = data.azurerm_management_group.target.id
  policy_definition_id = azurerm_policy_definition.auto_lighthouse_assignment[var.management_group_id].id
  location             = var.policy_assignment_location
  enforce              = true
  not_scopes = concat(
    [for mg in var.excluded_management_groups : "/providers/Microsoft.Management/managementGroups/${mg}"],
    [for sub in var.excluded_subscription_ids : "/subscriptions/${sub}"]
  )

  identity { type = "SystemAssigned" }

  parameters = jsonencode({
    lighthouseDefinitionId = { value = azurerm_lighthouse_definition.shared_lighthouse_definition.id }
  })

  depends_on = [azurerm_lighthouse_definition.shared_lighthouse_definition]
}

resource "azurerm_role_assignment" "auto_policy_identity_owner_exclude" {
  count              = var.mode == "exclude" ? 1 : 0
  scope              = data.azurerm_management_group.target.id
  role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635" # Owner
  principal_id       = azurerm_management_group_policy_assignment.auto_lighthouse_exclude[0].identity[0].principal_id
  principal_type     = "ServicePrincipal"
}

########################################################
# Automatic Remediation for Exclude Mode
########################################################

resource "azurerm_management_group_policy_remediation" "auto_lighthouse_exclude" {
  count                = var.mode == "exclude" ? 1 : 0
  name                 = "remediate-lighthouse-exclude"
  management_group_id  = data.azurerm_management_group.target.id
  policy_assignment_id = azurerm_management_group_policy_assignment.auto_lighthouse_exclude[0].id
  location_filters     = []
  failure_percentage   = 1.0
  parallel_deployments = 10
  resource_count       = 500

  depends_on = [
    azurerm_role_assignment.auto_policy_identity_owner_exclude
  ]
}

resource "azuread_application" "api" {
  display_name = "policy-enforcement-api-${var.accuknox_saas_client_id}"

  identifier_uris = [
    "api://${var.root_tenant_id}/${var.accuknox_saas_client_id}/policy-enforcement-api"
  ]

  app_role {
    id                   = var.accuknox_saas_client_id
    allowed_member_types = ["Application"]

    display_name = "Policy Administrator"
    description  = "Can create and manage Azure Policies"

    value   = "Policy.Admin"
    enabled = true
  }
}

#############################################
# API Service Principal
#############################################

resource "azuread_service_principal" "api" {
  client_id = azuread_application.api.client_id
}

#############################################
# SaaS Client Application
#############################################

resource "azuread_application" "client" {
  display_name = "policy-saas-client-${var.accuknox_saas_client_id}"
}

#############################################
# SaaS Client Service Principal
#############################################

resource "azuread_service_principal" "client" {
  client_id = azuread_application.client.client_id
}

#############################################
# Client Secret
#############################################

resource "azuread_application_password" "client" {
  application_id = azuread_application.client.id

  display_name = "terraform-generated-${var.accuknox_saas_client_id}"
}

#############################################
# Assign Policy.Admin role to SaaS client
#############################################

resource "azuread_app_role_assignment" "client_policy_admin" {
  principal_object_id = azuread_service_principal.client.object_id
  resource_object_id  = azuread_service_principal.api.object_id

  app_role_id = azuread_application.api.app_role_ids["Policy.Admin"]
}

#############################################
# Create Resource Group
#############################################

resource "azurerm_resource_group" "policy_enforcer_rg" {
  name     = "policy-enforcer-${var.accuknox_saas_client_id}"
  location = var.policy_management_resource_group_location
}

#############################################
# Create User assigned identity for azure functions
#############################################

resource "azurerm_user_assigned_identity" "policy_enforcer_uami" {
  name                = "policy-enforcement-uami-${var.accuknox_saas_client_id}"
  location            = var.policy_management_resource_group_location
  resource_group_name = azurerm_resource_group.policy_enforcer_rg.name

  tags = {
    "accuknox-saas-client-id" = var.accuknox_saas_client_id
    "accuknox-saas-tenant-id" = var.accuknox_saas_tenant_id
  }
}

#############################################
# Create Storage Account for azure functions
#############################################

resource "azurerm_storage_account" "policy_enforcer_storage" {
  name                = "pes${var.accuknox_saas_tenant_id}"
  resource_group_name = azurerm_resource_group.policy_enforcer_rg.name
  location            = var.policy_management_resource_group_location

  account_tier             = "Standard"
  account_replication_type = "LRS"
}

#############################################
# Create role assignments for user assigned identity
#############################################

resource "azurerm_role_assignment" "policy_enforcer_storage_blob_data_reader" {
  scope                = azurerm_storage_account.policy_enforcer_storage.id
  role_definition_name = "Storage Blob Data Contributor"

  principal_id = azurerm_user_assigned_identity.policy_enforcer_uami.principal_id

  depends_on = [
    azurerm_user_assigned_identity.policy_enforcer_uami,
    azurerm_storage_account.policy_enforcer_storage
  ]
}


resource "azurerm_role_assignment" "policy_enforcer_storage_blob_data_owner" {
  scope                = azurerm_storage_account.policy_enforcer_storage.id
  role_definition_name = "Storage Blob Data Owner"

  principal_id = azurerm_user_assigned_identity.policy_enforcer_uami.principal_id

  depends_on = [
    azurerm_user_assigned_identity.policy_enforcer_uami,
    azurerm_storage_account.policy_enforcer_storage
  ]
}

resource "azurerm_role_assignment" "policy_contributor_sami" {
  scope                = "/providers/Microsoft.Management/managementGroups/${var.root_tenant_id}"
  role_definition_name = "Resource Policy Contributor"

  principal_id = azurerm_function_app_flex_consumption.function.identity[0].principal_id

  depends_on = [
    azurerm_function_app_flex_consumption.function
  ]
}

resource "azurerm_role_assignment" "policy_user_access_administrator_sami" {
  scope                = "/providers/Microsoft.Management/managementGroups/${var.root_tenant_id}"
  role_definition_name = "User Access Administrator"

  principal_id = azurerm_function_app_flex_consumption.function.identity[0].principal_id

  depends_on = [
    azurerm_user_assigned_identity.policy_enforcer_uami
  ]
}

#############################################
# Create Flex Consumption Plan for azure functions
#############################################

resource "azurerm_service_plan" "policy_enforcer_flex_consumption_plan" {
  name                = "policy-flex-plan-${var.accuknox_saas_client_id}"
  location            = var.policy_management_resource_group_location
  resource_group_name = azurerm_resource_group.policy_enforcer_rg.name

  os_type  = "Linux"
  sku_name = "FC1"

}

#############################################
# Create storage container for azure functions
#############################################

resource "azurerm_storage_container" "package" {
  name                  = "app-package-${var.accuknox_saas_client_id}"
  storage_account_id    = azurerm_storage_account.policy_enforcer_storage.id
  container_access_type = "private"

  depends_on = [
    azurerm_storage_account.policy_enforcer_storage
  ]
}

#############################################
# Create Azure Function App
#############################################

resource "azurerm_function_app_flex_consumption" "function" {
  name                = "pe-function-${var.accuknox_saas_client_id}"
  location            = var.policy_management_resource_group_location
  resource_group_name = azurerm_resource_group.policy_enforcer_rg.name

  service_plan_id = azurerm_service_plan.policy_enforcer_flex_consumption_plan.id

  runtime_name    = "custom"
  runtime_version = "1.0"

  https_only                    = true
  enabled                       = true
  public_network_access_enabled = true

  instance_memory_in_mb  = 2048
  maximum_instance_count = 100

  storage_container_type     = "blobContainer"
  storage_container_endpoint = "${azurerm_storage_account.policy_enforcer_storage.primary_blob_endpoint}${azurerm_storage_container.package.name}"

  storage_authentication_type       = "UserAssignedIdentity"
  storage_user_assigned_identity_id = azurerm_user_assigned_identity.policy_enforcer_uami.id

  identity {
    type = "SystemAssigned, UserAssigned"

    identity_ids = [
      azurerm_user_assigned_identity.policy_enforcer_uami.id
    ]
  }

  app_settings = {
    TENANT_ID             = var.accuknox_saas_tenant_id
    TOPIC                 = "azurealerts"
    COMPONENT_NAME        = "cloud-governance"
    ALERTS_WEBHOOK_URL    = var.alerts_webhook_url
    AZURE_SUBSCRIPTION_ID = var.context_subscription_id
  }

  site_config {
    minimum_tls_version = "1.2"
  }

  tags = {
    "accuknox-saas-tenant-id" = var.accuknox_saas_tenant_id
    "accuknox-saas-client-id" = var.accuknox_saas_client_id
  }


  depends_on = [
    azurerm_role_assignment.policy_enforcer_storage_blob_data_reader,
    azurerm_storage_container.package,
    azurerm_storage_account.policy_enforcer_storage,
    azurerm_service_plan.policy_enforcer_flex_consumption_plan,
    azurerm_user_assigned_identity.policy_enforcer_uami,

  ]
}

#############################################
# Create API Management
#############################################

resource "azurerm_api_management" "apim" {
  name                = "pe-apim-${var.accuknox_saas_client_id}"
  location            = azurerm_resource_group.policy_enforcer_rg.location
  resource_group_name = azurerm_resource_group.policy_enforcer_rg.name

  publisher_name  = "Accuknox"
  publisher_email = "jones@accuknox.com"

  sku_name = "Developer_1"

  tags = {
    "accuknox-saas-tenant-id" = var.accuknox_saas_tenant_id
    "accuknox-saas-client-id" = var.accuknox_saas_client_id
  }
}

#############################################
# Create API Management API
#############################################

resource "azurerm_api_management_api" "policy_enforcement_api" {
  name                = "policy-enforcement-api-${var.accuknox_saas_client_id}"
  resource_group_name = azurerm_resource_group.policy_enforcer_rg.name
  api_management_name = azurerm_api_management.apim.name

  display_name = "Policy Enforcement API-${var.accuknox_saas_client_id}"
  revision     = "1"
  path         = "api"
  protocols    = ["https"]

  service_url           = "https://${azurerm_function_app_flex_consumption.function.default_hostname}/api"
  subscription_required = false


  depends_on = [
    azurerm_function_app_flex_consumption.function,
  ]
}

#############################################
# Create API Management API Operation
#############################################

resource "azurerm_api_management_api_operation" "enforce" {
  operation_id        = "enforce"
  api_name            = azurerm_api_management_api.policy_enforcement_api.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.policy_enforcer_rg.name

  display_name = "Enforce Policy"
  method       = "POST"
  url_template = "/policy"
  description  = "Enforce policy for accuknox saas client"

  response {
    status_code = 200
  }
}


#############################################
# Create API Management Policy
#############################################

resource "azurerm_api_management_api_policy" "policy" {
  api_name            = azurerm_api_management_api.policy_enforcement_api.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.policy_enforcer_rg.name

  xml_content = <<XML
<policies>
    <inbound>
        <base />

        <rate-limit-by-key
            calls="10"
            renewal-period="60"
            counter-key="@(context.Subscription?.Key ?? &quot;anonymous&quot;)" />

        <validate-jwt
            header-name="Authorization"
            failed-validation-httpcode="401">

            <openid-config url="https://login.microsoftonline.com/${var.root_tenant_id}/.well-known/openid-configuration" />

            <audiences>
                <audience>api://${var.root_tenant_id}/${var.accuknox_saas_client_id}/policy-enforcement-api</audience>
            </audiences>

            <required-claims>
                <claim name="roles" match="all">
                    <value>Policy.Admin</value>
                </claim>
            </required-claims>

        </validate-jwt>

    </inbound>

    <backend>
        <base />
    </backend>

    <outbound>
        <base />
    </outbound>

    <on-error>
        <base />
    </on-error>

</policies>
XML
}

########################################################
# Centralized Log Analytics Workspace
########################################################

resource "azurerm_log_analytics_workspace" "central" {
  name                = "accuknox-central-logs-${var.accuknox_saas_client_id}"
  location            = var.policy_management_resource_group_location
  resource_group_name = azurerm_resource_group.policy_enforcer_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    "accuknox-saas-tenant-id" = var.accuknox_saas_tenant_id
    "accuknox-saas-client-id" = var.accuknox_saas_client_id
  }
}

########################################################
# Subscription Diagnostic Settings → Central Workspace
########################################################

resource "azapi_resource" "subscription_diagnostic_settings" {
  for_each = toset(local.all_onboarded_subscription_ids)

  type      = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  name      = "accuknox-central-diag-${substr(each.value, 0, 8)}"
  parent_id = "/subscriptions/${each.value}"

  body = {
    properties = {
      workspaceId = azurerm_log_analytics_workspace.central.id
      logs = [
        { category = "Policy", enabled = true },
      ]
    }
  }

  depends_on = [azurerm_log_analytics_workspace.central]
}

########################################################
# Action Group for Policy Deny Alerts
########################################################

resource "azurerm_monitor_action_group" "policy_deny_alerts" {
  name                = "accuknox-policy-alerts-${var.accuknox_saas_client_id}"
  resource_group_name = azurerm_resource_group.policy_enforcer_rg.name
  location            = var.policy_management_resource_group_location
  short_name          = "ak-pol-deny"
  enabled             = true

  azure_function_receiver {
    name                     = "policy-deny-handler"
    function_app_resource_id = azurerm_function_app_flex_consumption.function.id
    function_name            = "alerts"
    http_trigger_url         = "https://${azurerm_function_app_flex_consumption.function.default_hostname}/api/alerts"
    use_common_alert_schema  = true
  }

  tags = {
    "accuknox-saas-tenant-id" = var.accuknox_saas_tenant_id
    "accuknox-saas-client-id" = var.accuknox_saas_client_id
  }
}

########################################################
# Activity Log Alert for Policy Deny Events
########################################################

resource "azurerm_monitor_activity_log_alert" "policy_deny" {
  name                = "accuknox-policy-deny-alert-${var.accuknox_saas_client_id}"
  resource_group_name = azurerm_resource_group.policy_enforcer_rg.name
  location            = "global"
  enabled             = true
  scopes              = [for sub_id in local.all_onboarded_subscription_ids : "/subscriptions/${sub_id}"]

  criteria {
    category       = "Policy"
    operation_name = "Microsoft.Authorization/policies/deny/action"
  }

  action {
    action_group_id = azurerm_monitor_action_group.policy_deny_alerts.id
  }

  tags = {
    "accuknox-saas-tenant-id" = var.accuknox_saas_tenant_id
    "accuknox-saas-client-id" = var.accuknox_saas_client_id
  }
}

#############################################
# Outputs
#############################################

output "tenant_id" {
  value = data.azuread_client_config.current.tenant_id
}

output "audience_uri" {
  value = "api://${var.root_tenant_id}/${var.accuknox_saas_client_id}/policy-enforcement-api"
}

output "client_id" {
  value = azuread_application.client.client_id
}

output "client_secret" {
  value     = azuread_application_password.client.value
  sensitive = true
}

output "apim_invoke_url" {
  value = azurerm_api_management_api.policy_enforcement_api.service_url
}

output "onboarded_subscription_count" {
  value = length(local.all_onboarded_subscription_ids)
}
