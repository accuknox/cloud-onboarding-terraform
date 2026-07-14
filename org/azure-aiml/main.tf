########################################################
#   - Cognitive Services User + OpenAI User (via Lighthouse delegation)
#   - Microsoft Graph application permissions (via azuread, gated)
#   - Power Platform: register AccuKnox app as Service Reader app user
########################################################


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
      version = ">= 2.47.0"
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
  default     = "context-management-group"
}

variable "context_subscription_id" {
  description = "Subscription ID where the shared lighthouse definition will be created"
  type        = string
  default     = "context_subscription_id"

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
      principal_id           = "47e2ce34-c78d-4aaf-8f5f-300ec63c907f" # AccuKnox App Register
      principal_display_name = "AccuKnox CSPM Reader"
      role_definition_id     = "acdd72a7-3385-48ef-bd42-f606fba81ae7" # Reader
    },
    {
      principal_id           = "cc2d4923-7605-4505-82e2-5235216d03fc"
      principal_display_name = "AccuKnox Scanner"
      role_definition_id     = "acdd72a7-3385-48ef-bd42-f606fba81ae7" # Reader
    },
  ]
}



variable "mode" {
  description = "Onboarding mode: 'include' or 'exclude'"
  type        = string
  default     = "include"

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
  default     = [""]
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
  default     = ["exclude-management-group-id-1", "exclude-management-group-id-2"]
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


########################################################
# Graph Permission Variables
########################################################

variable "enable_graph_permissions" {
  description = "Whether to grant Microsoft Graph application permissions to the AccuKnox service principal. Requires the operator to have Privileged Role Administrator / Global Administrator in the customer tenant. Set to false to skip."
  type        = bool
  default     = true
}

variable "accuknox_app_client_id" {
  description = "Client (application) ID of the AccuKnox enterprise app / service principal in the customer tenant, used for Graph permission grants and the Power Platform application user."
  type        = string
  default     = "384d0c6d-8e35-489a-8833-346c5bbf2dbc"
}

variable "graph_app_role_ids" {
  description = "Microsoft Graph application role (app role) IDs to grant + consent to the AccuKnox service principal."
  type        = list(string)
  default = [
    "7ab1d382-f21e-4acd-a863-ba3e13f7da61", # Directory.Read.All
    "9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30", # Application.Read.All
    "b0afded3-3588-46d8-8b3d-9842eff778da", # AuditLog.Read.All
    "20e6f8e4-ffac-4cf7-82f7-70ddb7564318", # AuditLogsQuery-CRM.Read.All
    "5e1e9171-754d-478c-812c-f1755a9a4c2d", # AuditLogsQuery.Read.All
  ]
}


########################################################
# Power Platform Variables
########################################################

variable "enable_powerplatform_registration" {
  description = "Register the AccuKnox app as a Service Reader application user in Power Platform (Dataverse) environments. Set false to skip (and avoid needing Power Platform auth)."
  type        = bool
  default     = true
}

variable "powerplatform_environment_selection" {
  description = "'all' = every Dataverse environment the operator can access (from the API); 'specific' = only those in only_environment_display_names."
  type        = string
  default     = "all"
  validation {
    condition     = contains(["all", "specific"], var.powerplatform_environment_selection)
    error_message = "powerplatform_environment_selection must be 'all' or 'specific'."
  }
}

variable "only_environment_display_names" {
  description = "Environment display names to onboard when powerplatform_environment_selection = 'specific'. Ignored when selection = 'all'."
  type        = list(string)
  default     = []
}

variable "dataverse_security_role_name" {
  description = "Dataverse security role assigned to the AccuKnox application user."
  type        = string
  default     = "Service Reader"
}

variable "powerplatform_api_version" {
  description = "BAP API version used for environment discovery."
  type        = string
  default     = "2021-04-01"
}

########################################################
# Custom ML Scanner Role Variables
########################################################

variable "ml_scanner_role_name" {
  description = "Name of the custom role granting AccuKnox the ML secret/key-listing actions needed for dataset scanning. Must be unique within the customer tenant."
  type        = string
  default     = "AccuKnox ML Scanner"
}

variable "ml_scanner_custom_role_actions" {
  description = "Control-plane actions for the custom ML scanner role. These are management-plane '*/action' / '*/read' permissions (they go in 'actions', not 'data_actions') and are assigned directly per subscription — NOT via Lighthouse, which rejects custom roles."
  type        = list(string)
  default = [
    "Microsoft.MachineLearningServices/workspaces/onlineEndpoints/score/action",
    "Microsoft.MachineLearningServices/workspaces/serverlessEndpoints/listKeys/action",
    "Microsoft.MachineLearningServices/workspaces/listStorageAccountKeys/action",
    "Microsoft.MachineLearningServices/workspaces/datastores/listSecrets/action",
    "Microsoft.CognitiveServices/accounts/listKeys/action",
    "Microsoft.CognitiveServices/accounts/deployments/read",
    "Microsoft.Storage/storageAccounts/listKeys/action",
  ]
}



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
    az graph query -q "ResourceContainers | where type == 'microsoft.resources/subscriptions' | extend mgChain = properties.managementGroupAncestorsChain | where mgChain has '${each.value}' | project subscriptionId" --query "{ subscriptions: to_string(data[].subscriptionId) }" -o json
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
}

########################################################
# Resource Provider Registration
########################################################

resource "azurerm_resource_provider_registration" "managed_services" {
  name = "Microsoft.ManagedServices"
}

########################################################
# Shared Lighthouse Registration Definition
########################################################

resource "azurerm_lighthouse_definition" "shared_lighthouse_definition" {
  depends_on = [azurerm_resource_provider_registration.managed_services]
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
# Microsoft Graph Application Permissions
# (Entra ID app role assignments — NOT delegable via Lighthouse)
# Gated behind var.enable_graph_permissions. Requires the operator to
# have Privileged Role Administrator / Global Administrator in the
# customer's Entra tenant.
########################################################

data "azuread_service_principal" "msgraph" {
  count     = var.enable_graph_permissions ? 1 : 0
  client_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
}

# The AccuKnox enterprise app (service principal) in the customer tenant
data "azuread_service_principal" "accuknox" {
  count     = var.enable_graph_permissions ? 1 : 0
  client_id = var.accuknox_app_client_id
}

resource "azuread_app_role_assignment" "accuknox_graph" {
  for_each            = var.enable_graph_permissions ? toset(var.graph_app_role_ids) : []
  app_role_id         = each.value
  principal_object_id = data.azuread_service_principal.accuknox[0].object_id
  resource_object_id  = data.azuread_service_principal.msgraph[0].object_id
}

########################################################
# Cognitive Services Direct Role Assignments
# Lighthouse blocks roles with data actions, so these
# must be assigned directly on each subscription.
########################################################

locals {
  cognitive_role_ids = [
    "a97b65f3-24c7-4388-baec-2e87135dc908", # Cognitive Services User
    "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd", # Cognitive Services OpenAI User
    "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1", # Storage Blob Data Reader
  ]

  all_target_subscription_ids = var.mode == "include" ? distinct(concat(
    local.include_mode_subscription_ids,
    local.filtered_include_extra_subscription_ids
    )) : distinct(concat(
    local.exclude_mode_subscription_ids,
    local.filtered_include_exception_subscription_ids
  ))

  cognitive_assignments = var.enable_graph_permissions ? {
    for pair in setproduct(local.all_target_subscription_ids, local.cognitive_role_ids) :
    "${pair[0]}__${pair[1]}" => { subscription_id = pair[0], role_id = pair[1] }
  } : {}
}

resource "azurerm_role_assignment" "accuknox_cognitive_services" {
  for_each           = local.cognitive_assignments
  scope              = "/subscriptions/${each.value.subscription_id}"
  role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/${each.value.role_id}"
  principal_id       = data.azuread_service_principal.accuknox[0].object_id
  principal_type     = "ServicePrincipal"
}

########################################################
# Custom ML Scanner Role + Direct Assignment
########################################################

# Custom role defined at the target MG so it is assignable on all child subscriptions.
resource "azurerm_role_definition" "accuknox_ml_scanner" {
  name        = var.ml_scanner_role_name
  scope       = data.azurerm_management_group.target.id
  description = "AccuKnox CSPM: retrieve ML datastore/storage secrets and endpoint keys for dataset scanning"

  permissions {
    actions = var.ml_scanner_custom_role_actions
    # All are management-plane actions; no data_actions / not_actions required.
    not_actions = []
  }

  assignable_scopes = distinct(concat(

    [data.azurerm_management_group.target.id],

    [for sub in local.all_target_subscription_ids : "/subscriptions/${sub}"]

  ))
}

# Direct per-subscription assignment of the custom role (gated like the cognitive block,
# since it depends on the AccuKnox SP looked up only when enable_graph_permissions is true).
resource "azurerm_role_assignment" "accuknox_ml_scanner" {
  for_each           = var.enable_graph_permissions ? toset(local.all_target_subscription_ids) : []
  scope              = "/subscriptions/${each.value}"
  role_definition_id = azurerm_role_definition.accuknox_ml_scanner.role_definition_resource_id
  principal_id       = data.azuread_service_principal.accuknox[0].object_id
  principal_type     = "ServicePrincipal"

  # Ensure the role definition has propagated before assigning it.
  depends_on = [azurerm_role_definition.accuknox_ml_scanner]
}


########################################################
# Power Platform — register AccuKnox app as a Service Reader
########################################################

# 1) Discover accessible Dataverse environments via the BAP API.
data "external" "powerplatform_environments" {
  count = var.enable_powerplatform_registration ? 1 : 0
  program = ["bash", "-c", <<-EOT
    az rest --method get \
      --url "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments?api-version=${var.powerplatform_api_version}&%24expand=properties.linkedEnvironmentMetadata" \
      --resource "https://api.bap.microsoft.com/" --only-show-errors \
      --query "{ envs: to_string(value[?properties.linkedEnvironmentMetadata.instanceUrl].{ id: name, name: properties.displayName, url: properties.linkedEnvironmentMetadata.instanceUrl }) }" \
      -o json
  EOT
  ]
}

locals {
  pp_all_envs = var.enable_powerplatform_registration ? jsondecode(
    data.external.powerplatform_environments[0].result.envs
  ) : []

  # Apply the enable/all/specific selection; normalise the Dataverse URL
  dataverse_envs = {
    for env in local.pp_all_envs :
    env.id => {
      id   = env.id
      name = env.name
      url  = trimsuffix(env.url, "/")
    }
    if var.powerplatform_environment_selection == "all" ||
    contains(var.only_environment_display_names, env.name)
  }
}

# 2/3) Create (and, on destroy, remove) the AccuKnox application user per env.
resource "terraform_data" "pp_app_user" {
  for_each = local.dataverse_envs

  input = {
    url       = each.value.url
    env_id    = each.value.id
    env_name  = each.value.name
    app_id    = var.accuknox_app_client_id
    role_name = var.dataverse_security_role_name
  }

  # Re-run create if any of these change.
  triggers_replace = {
    url       = each.value.url
    app_id    = var.accuknox_app_client_id
    role_name = var.dataverse_security_role_name
  }

  # ---- CREATE ----
  provisioner "local-exec" {
    when        = create
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -uo pipefail
      base="${self.input.url}/api/data/v9.2"
      res="${self.input.url}"
      app="${self.input.app_id}"
      role="${self.input.role_name}"
      env="${self.input.env_name}"

      bu=$(az rest --method get \
        --url "$base/businessunits?%24select=businessunitid&%24filter=parentbusinessunitid%20eq%20null" \
        --resource "$res" --only-show-errors --query "value[0].businessunitid" -o tsv 2>/dev/null)
      if [ -z "$bu" ]; then echo "SKIP $env: no Dataverse access"; exit 0; fi

      roleid=$(az rest --method get \
        --url "$base/roles?%24select=roleid&%24filter=name%20eq%20'$role'%20and%20_businessunitid_value%20eq%20$bu" \
        --resource "$res" --only-show-errors --query "value[0].roleid" -o tsv)
      if [ -z "$roleid" ]; then echo "ERROR $env: role '$role' not found" >&2; exit 1; fi

      uid=$(az rest --method get \
        --url "$base/systemusers?%24select=systemuserid&%24filter=applicationid%20eq%20$app" \
        --resource "$res" --only-show-errors --query "value[0].systemuserid" -o tsv)

      # Create if missing.
      if [ -z "$uid" ]; then
        uid=$(az rest --method post --url "$base/systemusers" --resource "$res" \
          --headers "Content-Type=application/json" "Prefer=return=representation" \
          --body "{\"applicationid\":\"$app\",\"businessunitid@odata.bind\":\"/businessunits($bu)\"}" \
          --only-show-errors --query "systemuserid" -o tsv)
        if [ -z "$uid" ]; then
          echo "ERROR $env: could not create app user (operator needs System Administrator in this env)" >&2
          exit 1
        fi
      fi

      az rest --method patch --url "$base/systemusers($uid)" --resource "$res" \
        --headers "Content-Type=application/json" --body '{"isdisabled":false}' \
        --only-show-errors \
        || echo "WARN $env: could not enable app user $uid (missing prvWriteUser?)" >&2

      err=$(mktemp)
      if az rest --method post \
        --url "$base/systemusers($uid)/systemuserroles_association/%24ref" \
        --resource "$res" --headers "Content-Type=application/json" \
        --body "{\"@odata.id\":\"$base/roles($roleid)\"}" \
        --only-show-errors 2>"$err"; then
        echo "OK $env: app user $uid ($role assigned)"
      elif grep -qiE 'duplicate|already' "$err"; then
        echo "OK $env: app user $uid ($role already assigned)"
      else
        echo "WARN $env: app user $uid present but role NOT assigned:" >&2
        cat "$err" >&2
      fi
      rm -f "$err"
    EOT
  }

  # ---- DESTROY ---- (look up fresh, disable, then delete)
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -uo pipefail
      base="${self.input.url}/api/data/v9.2"
      res="${self.input.url}"
      app="${self.input.app_id}"
      env="${self.input.env_name}"

      uid=$(az rest --method get \
        --url "$base/systemusers?%24select=systemuserid&%24filter=applicationid%20eq%20$app" \
        --resource "$res" --only-show-errors --query "value[0].systemuserid" -o tsv 2>/dev/null)
      if [ -z "$uid" ]; then echo "SKIP $env: nothing to remove"; exit 0; fi

      # NOTE: Dataverse does NOT allow hard-deleting a systemuser / application
      if az rest --method patch --url "$base/systemusers($uid)" --resource "$res" \
        --headers "Content-Type=application/json" --body '{"isdisabled":true}' \
        --only-show-errors; then
        echo "DISABLED $env: app user $uid (access revoked; record retained by design)"
      else
        echo "WARN $env: could NOT disable app user $uid — operator lacks prvWriteUser (System Administrator) here; disable it manually in the Power Platform admin center" >&2
      fi
    EOT
  }
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

  not_scopes = [for sub in var.excluded_subscription_ids : "/subscriptions/${sub}"]

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
  count               = length(local.filtered_included_management_group_ids)
  name                = lower("remediate-lighthouse-${replace(local.filtered_included_management_group_ids[count.index], "/[^a-zA-Z0-9-]/", "-")}")
  management_group_id = "/providers/Microsoft.Management/managementGroups/${local.filtered_included_management_group_ids[count.index]}"
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

########################################################
# Power Platform Outputs
########################################################
output "powerplatform_selected_environments" {
  description = "Environments selected for AccuKnox app-user registration (display name => Dataverse URL)."
  value       = { for id, env in local.dataverse_envs : env.name => env.url }
}
