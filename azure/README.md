Azure Lighthouse: Auto-Onboard Subscriptions under a Management Group (Terraform)

Purpose
- Define and assign a custom Azure Policy at a management group (MG) that uses deployIfNotExists to create Lighthouse delegation in every subscription under that MG. Keeps future subscriptions auto-onboarded.

What This Module Creates
- Custom Policy Definition at the MG: Enforces that each subscription has an Azure Lighthouse registration targeting AccuKnox, using your authorizations.
- Policy Assignment at the MG with a system-assigned managed identity.
- Remediation Task to evaluate existing subscriptions and deploy Lighthouse where missing.

Inputs
- `management_group_id` (required): MG ID (name), e.g., `my-root-mg-id`.
- `managing_tenant_id` (required): AccuKnox tenant GUID.
- `offer_name` / `offer_description`: Surfaced in the customer's Service providers blade.
- `authorizations` (required): Array of objects:
  - `principal_id`: Object ID in AccuKnox tenant (group/SP/MI).
  - `principal_display_name`: Friendly name for auditability.
  - `role_definition_id`: Role GUID (e.g., Reader = `acdd72a7-3385-48ef-bd42-f606fba81ae7`, Security Reader = `b0f54661-2d74-4c50-afa3-1ec803f12efe`).
  - `delegated_role_definition_ids` (optional): If using a `User Access Administrator` principal for policy remediation scenarios.
- `remediation_role_definition_ids`: Role GUIDs the policy identity must have at subscription scope to deploy (default = `Owner`).
- `policy_assignment_location`: Region for the policy assignment identity.

Permissions Required (Akshay side)
- To create policy definition/assignment at MG: Resource Policy Contributor or Owner on the MG.
- For the policy identity to deploy in subscriptions: The assignment uses `roleDefinitionIds` (default Owner) to grant necessary rights at the subscription scope during remediation.
- Microsoft.ManagedServices RP must be registered in each subscription. See Notes.

Usage
1) Configure variables (see `terraform/lighthouse_mg_policy/terraform.tfvars.example`).

2) Authenticate to Akshay's tenant with sufficient rights at the MG:
   - `az login --tenant <AkshayTenantId>`

3) Deploy:
   - `cd terraform/lighthouse_mg_policy`
   - `terraform init`
   - `terraform plan`
   - `terraform apply`

4) Validate:
   - AccuKnox tenant → Azure Portal → My customers: subscriptions from the MG appear with delegated access.
   - Policy compliance shows non-compliant subscriptions until remediation completes.

## Requirements for Automatic Onboarding of New Subscriptions

For new subscriptions to be automatically onboarded by the policy, they must meet these requirements:

### 1. Management Group Placement
- New subscriptions must be placed under the management group where the Lighthouse policy is assigned (or any nested child management groups)
- The policy inherits down the management group hierarchy
- Use Azure Portal → Management Groups to move subscriptions to the correct location

### 2. Resource Provider Registration
New subscriptions need these resource providers registered:
- **Microsoft.PolicyInsights** - Required for policy evaluation and compliance
- **Microsoft.ManagedServices** - Required for Lighthouse delegation

**To register via Azure Portal:**
1. Go to Azure Portal → Subscriptions → [Your Subscription]
2. Click "Resource providers" in left menu
3. Search for and register both providers above

### 3. Policy Evaluation Time
- After meeting the above requirements, allow 15-30 minutes for automatic policy evaluation
- The policy will create Lighthouse delegation automatically using `deployIfNotExists` effect

## Onboarding Modes

The template supports sophisticated include/exclude patterns for maximum flexibility:

### Mode 1: Exclude Mode (Default)
```hcl
mode = "exclude"
```
**Strategy**: "Onboard everything except..."

Assigns policy to the root management group but excludes specific items:

```hcl
# Exclude entire management groups
excluded_management_groups = ["mg-production", "sensitive-workloads"]

# Exclude specific subscriptions globally
excluded_subscription_ids = ["sub-id-1", "sub-id-2"]

# Include exceptions (subscriptions to include even if their MG is excluded)
include_exception_subscription_ids = ["special-prod-sub-id"]
```

**How it works:**
1. Single policy assignment to root management group
2. Excludes specified management groups and subscriptions
3. Creates individual assignments for exception subscriptions

### Mode 2: Include Mode
```hcl
mode = "include"
```
**Strategy**: "Only onboard these specific things..."

Assigns policy only to specified management groups and subscriptions:

```hcl
# Include specific management groups
included_management_group_ids = ["cspm-development", "mg-development"]

# Exclude subscriptions from the included MGs
excluded_subscription_ids = ["test-sub-in-dev-mg"]

# Include extra subscriptions outside the included MGs
include_extra_subscription_ids = ["standalone-sub-id"]
```

**How it works:**
1. Individual policy assignments to each included management group
2. Excludes specified subscriptions within those groups
3. Creates separate assignments for extra subscriptions outside the groups

### Use Cases

**Exclude Mode** - Best for broad organizational onboarding:
- "Onboard everything except production and compliance environments"
- "Onboard all dev/test but exclude this one sensitive subscription"

**Include Mode** - Best for targeted/phased onboarding:
- "Start with development environments only"
- "Onboard these specific business units and this one pilot subscription"

## Notes
- Management group scope vs. actions: Lighthouse still delegates per subscription. You'll operate against individual subscriptions even though onboarding is MG-wide.
- `management_group_id` is the Group ID (name), NOT a GUID. Find it via: `az account management-group list --query "[].{name:name,displayName:displayName}" -o table`.
- `policy_assignment_name` must be ≤ 24 chars. Use a short slug like `lh-enforce` (display name can be long).
- Roles to delegate via Lighthouse: For read-only CSPM, commonly `Reader`, `Security Reader`, optionally `Reader and Data Access` and `Policy Insights Data Reader`.
 - Future subscriptions: Keep the policy assignment in place; Azure Policy will evaluate new subscriptions added to the MG and deploy Lighthouse automatically.

## Remediation Script (Trigger deployIfNotExists)
- Purpose: Create remediation tasks for all relevant policy assignments so Lighthouse definitions/assignments are deployed.
- Prereqs: Azure CLI logged into Akshay's tenant; `Microsoft.ManagedServices` RP registered in each target subscription.
- Steps:
  - Get the policy definition ID: `terraform -chdir=terraform/lighthouse_mg_policy output -raw policy_definition_id`
  - Run: `scripts/create_lighthouse_remediations.sh --mg-id <MG_ID> --policy-definition-id "$(terraform -chdir=terraform/lighthouse_mg_policy output -raw policy_definition_id)"`
  - Optional: add `--dry-run` to preview commands.

---

## Tenant Ownership Verification (Preventing Confused Deputy Attack)

### Problem Statement
In a multi-tenant SaaS scenario, we need to prevent the "confused deputy problem" where:
- Customer A onboards their Azure tenant and creates a Lighthouse delegation
- Malicious Customer B tries to claim Customer A's tenant by entering their Tenant ID
- Without verification, Customer B could gain access to Customer A's data

### Solution: Verification Token Pattern (AWS External ID Equivalent)

We implement a security mechanism similar to AWS's External ID pattern for cross-account access:

**Security Principle:** Each customer receives a unique, cryptographically random token that must be embedded in their Lighthouse offer name. Only the customer who possesses the token can prove ownership of the delegation.

---

### Backend Integration Flow

#### **Step 1: Customer Initiates Onboarding (AccuKnox Backend)**

When a customer starts Azure onboarding in the AccuKnox platform:

```python
import secrets

def initiate_azure_onboarding(customer_id: str) -> dict:
    """
    Generate unique verification token for customer
    IMPORTANT: Backend MUST generate token, NOT customer
    """
    # Generate cryptographically secure token
    verification_token = f"AK-CNAPP-{secrets.token_urlsafe(16)}"

    # Store in database
    db.onboarding_tokens.insert({
        "customer_id": customer_id,
        "token": verification_token,
        "created_at": datetime.now(),
        "expires_at": datetime.now() + timedelta(days=7),
        "status": "pending"
    })

    return {
        "verification_token": verification_token,
        "terraform_download_url": f"/api/download/terraform?token={verification_token}"
    }
```

**What Customer Receives:**
- Unique verification token: `AK-CNAPP-abc123xyz`
- Pre-configured Terraform package with token embedded in `terraform.tfvars`

---

#### **Step 2: Generate terraform.tfvars (AccuKnox Backend)**

The backend generates a `terraform.tfvars` file with the token pre-filled:

```hcl
# Auto-generated by AccuKnox - DO NOT MODIFY
accuknox_verification_token = "AK-CNAPP-abc123xyz"

# Customer fills these values
management_group_id     = "YOUR_MANAGEMENT_GROUP_ID"
context_subscription_id = "YOUR_SUBSCRIPTION_ID"
managing_tenant_id      = "3d64034d-3c3e-4959-b019-f15558be8a4e"  # AccuKnox tenant (pre-filled)

mode = "exclude"  # or "include"

# ... rest of configuration
```

**Key Points:**
- `accuknox_verification_token` is pre-filled and marked as DO NOT MODIFY
- `managing_tenant_id` is pre-filled with AccuKnox's tenant ID
- Customer only needs to provide their own infrastructure details

---

#### **Step 3: Customer Deploys Terraform**

Customer runs terraform in their Azure tenant:

```bash
az login --tenant <customer-tenant-id>
cd terraform/lighthouse_mg_policy
terraform init
terraform plan
terraform apply
```

**What Gets Created:**
- Lighthouse definition with name: `"AccuKnox CSPM Integration - AK-CNAPP-abc123xyz"`
- Lighthouse assignment linking definition to customer's subscriptions
- The verification token is now **permanently embedded** in Azure Lighthouse metadata

---

#### **Step 4: Customer Completes Onboarding (AccuKnox UI)**

Customer returns to AccuKnox platform and provides:

**Option A: Minimal Input (Recommended)**
- Tenant ID only (token already known from session)

**Option B: Full Input**
- Tenant ID: `61d92e2e-f113-48ee-9d3f-2f81628fd5d5`
- Verification Token: `AK-CNAPP-abc123xyz` (from terraform output)

---

#### **Step 5: Backend Verification (AccuKnox)**

```python
from azure.mgmt.managedservices import ManagedServicesClient
from azure.identity import DefaultAzureCredential

def verify_tenant_ownership(
    customer_id: str,
    claimed_tenant_id: str,
    verification_token: str
) -> dict:
    """
    Verify customer owns the Azure tenant by checking Lighthouse delegation
    contains their unique verification token
    """

    # 1. Validate token belongs to this customer
    token_record = db.onboarding_tokens.find_one({
        "customer_id": customer_id,
        "token": verification_token,
        "status": "pending"
    })

    if not token_record:
        return {"verified": False, "error": "Invalid verification token"}

    if token_record["expires_at"] < datetime.now():
        return {"verified": False, "error": "Token expired"}

    # 2. Query Azure Lighthouse API (as AccuKnox)
    credential = DefaultAzureCredential()
    client = ManagedServicesClient(
        credential=credential,
        subscription_id=ACCUKNOX_SUBSCRIPTION_ID
    )

    # 3. List all delegations to AccuKnox
    assignments = client.registration_assignments.list(
        scope=f"/subscriptions/{ACCUKNOX_SUBSCRIPTION_ID}"
    )

    # 4. Search for delegation with verification token
    for assignment in assignments:
        reg_def = assignment.properties.registration_definition.properties

        offer_name = reg_def.registration_definition_name
        managee_tenant = reg_def.managee_tenant_id  # Customer's tenant
        managing_tenant = reg_def.managed_by_tenant_id  # AccuKnox tenant

        # Check if this delegation matches
        if (verification_token in offer_name and
            managee_tenant == claimed_tenant_id and
            managing_tenant == ACCUKNOX_TENANT_ID):

            # VERIFIED! Customer owns this tenant

            # Mark token as used (single-use)
            db.onboarding_tokens.update_one(
                {"token": verification_token},
                {"$set": {"status": "used", "used_at": datetime.now()}}
            )

            # Link tenant to customer
            db.customers.update_one(
                {"id": customer_id},
                {"$set": {
                    "azure_tenant_id": claimed_tenant_id,
                    "lighthouse_definition_id": assignment.properties.registration_definition_id,
                    "verified_at": datetime.now(),
                    "status": "active"
                }}
            )

            return {
                "verified": True,
                "tenant_id": claimed_tenant_id,
                "offer_name": offer_name
            }

    return {
        "verified": False,
        "error": "No Lighthouse delegation found with verification token"
    }
```

---

### Security Guarantees

#### **Why This Prevents Confused Deputy Attack:**

**Attack Scenario:**
1. Customer A gets token: `AK-CNAPP-aaa111`
2. Customer A deploys Lighthouse with token in offer name
3. Customer B gets token: `AK-CNAPP-bbb222`
4. Customer B tries to claim Customer A's tenant ID

**Why Attack Fails:**
- AccuKnox searches for delegation with `AK-CNAPP-bbb222` in offer name
- Only finds Customer A's delegation with `AK-CNAPP-aaa111`
- Token mismatch → Claim rejected ❌

**Additional Security Properties:**
- Customer B cannot create Lighthouse delegation in Customer A's tenant (no Azure permissions)
- Customer B cannot guess Customer A's token (cryptographically random, 128+ bits entropy)
- Token is single-use (marked as "used" after successful verification)
- Token expires after 7 days (prevents delayed attacks)

---

### Azure CLI Verification Commands

**From AccuKnox Tenant (for testing/debugging):**

```bash
# Login as AccuKnox
az login --tenant 3d64034d-3c3e-4959-b019-f15558be8a4e

# List all delegations to AccuKnox
az managedservices assignment list --include-definition \
  --query "[].{OfferName:properties.registrationDefinition.properties.registrationDefinitionName, CustomerTenant:properties.registrationDefinition.properties.manageeTenantId}" \
  -o table

# Expected output:
# OfferName                                            CustomerTenant
# ---------------------------------------------------  ------------------------------------
# AccuKnox CSPM Integration - AK-CNAPP-abc123xyz      61d92e2e-f113-48ee-9d3f-2f81628fd5d5
```

**Detailed JSON inspection:**

```bash
az managedservices assignment list --include-definition -o json | jq '.[] | {
  offerName: .properties.registrationDefinition.properties.registrationDefinitionName,
  customerTenant: .properties.registrationDefinition.properties.manageeTenantId,
  managingTenant: .properties.registrationDefinition.properties.managedByTenantId
}'
```

---

### Database Schema

**onboarding_tokens collection:**
```javascript
{
  "token": "AK-CNAPP-abc123xyz",
  "customer_id": "cust-12345",
  "created_at": ISODate("2025-10-07T10:30:00Z"),
  "expires_at": ISODate("2025-10-14T10:30:00Z"),
  "status": "pending",  // pending | used | expired
  "used_at": null,
  "tenant_id": null  // populated after verification
}
```

**customers collection (updated after verification):**
```javascript
{
  "id": "cust-12345",
  "azure_tenant_id": "61d92e2e-f113-48ee-9d3f-2f81628fd5d5",
  "lighthouse_definition_id": "/subscriptions/.../registrationDefinitions/...",
  "verified_at": ISODate("2025-10-07T10:35:00Z"),
  "status": "active"
}
```

---

### User Experience Flow

```
1. Customer logs into AccuKnox
   ↓
2. Clicks "Onboard Azure Organization"
   ↓
3. AccuKnox generates token: AK-CNAPP-abc123xyz
   ↓
4. Customer downloads pre-configured Terraform package
   (token already in terraform.tfvars)
   ↓
5. Customer runs: terraform apply
   (creates Lighthouse with token in offer name)
   ↓
6. Customer returns to AccuKnox, enters Tenant ID
   ↓
7. AccuKnox verifies:
   - Queries Lighthouse API
   - Finds delegation with matching token
   - Extracts customer tenant ID
   - Verifies it matches claimed tenant
   ↓
8. Success! Tenant linked to customer account ✅
```

---

### Best Practices

1. **Token Generation:**
   - Use cryptographically secure random generation (`secrets.token_urlsafe()`)
   - Minimum 128 bits of entropy
   - Include identifiable prefix (`AK-CNAPP-`)

2. **Token Storage:**
   - Store with customer_id for lookup
   - Set expiration (7 days recommended)
   - Mark as single-use after verification

3. **Verification:**
   - Always validate token belongs to requesting customer
   - Check token expiration before querying Azure
   - Verify both token AND tenant ID match
   - Mark token as used after successful verification

4. **Error Handling:**
   - Token expired → Generate new token
   - Token not found → Invalid customer session
   - Delegation not found → Customer hasn't deployed Terraform yet
   - Token mismatch → Potential attack, log and alert

5. **Monitoring:**
   - Log all verification attempts
   - Alert on multiple failed attempts from same customer
   - Track token usage metrics (time to deployment, success rate)

---

### API Endpoint Examples

**Initiate Onboarding:**
```http
POST /api/v1/azure/onboarding/start
Authorization: Bearer <customer-jwt>

Response:
{
  "verification_token": "AK-CNAPP-abc123xyz",
  "terraform_download_url": "/api/download/terraform?token=abc...",
  "expires_at": "2025-10-14T10:30:00Z"
}
```

**Complete Onboarding:**
```http
POST /api/v1/azure/onboarding/complete
Authorization: Bearer <customer-jwt>
Content-Type: application/json

{
  "tenant_id": "61d92e2e-f113-48ee-9d3f-2f81628fd5d5",
  "verification_token": "AK-CNAPP-abc123xyz"
}

Response:
{
  "verified": true,
  "tenant_id": "61d92e2e-f113-48ee-9d3f-2f81628fd5d5",
  "message": "Azure tenant successfully linked"
}
```
