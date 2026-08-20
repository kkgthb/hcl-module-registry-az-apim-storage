data "azurerm_client_config" "current_azurerm_config" {
  lifecycle {
    postcondition {
      condition     = (coalesce(self.client_id, "") == "04b07795-8ddb-461a-bbee-02f9e1bf7b46")
      error_message = "AzureRM login state client ID, in submodule, is not the well-known Azure CLI GUID."
    }
    postcondition {
      condition     = (coalesce(self.object_id, "") != "")
      error_message = "AzureRM login state, in submodule, does not bear a logged-in user object ID."
    }
  }
}

resource "azurerm_storage_container" "enterprise_hcl_mod_reg_storacct_container" {
  name                  = "enterprise-hcl-mod-reg-container"
  storage_account_id    = var.storacct_instance.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "enterprise_hcl_mod_reg_storacct_container_blob_data_contributor_roleassignment" {
  principal_id         = data.azurerm_client_config.current_azurerm_config.object_id # Realistically, a Security Group of module authors, but I'll do for now.
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_container.enterprise_hcl_mod_reg_storacct_container.id
}

# TODO:  `azurerm_api_management_api` 
# with a `Segment`-typed `versioning_scheme`'ed `azurerm_api_management_api_version_set`, 
# with an all-operations-API-wide `azurerm_api_management_api_policy`, 
# with an `azurerm_api_management_api_operation_policy` against the `list-versions` operation, 
# with an `azurerm_api_management_api_operation_policy` against the `download-module` operation, and
# with an `azurerm_api_management_api_operation_policy` against the `download-archive` operation.

resource "azurerm_api_management_api_version_set" "ehmr_api_version_set" {
  name                = "enterprise-hcl-mod-reg-api-version-set"
  display_name        = "Enterprise-wide HCL module registry API version set"
  api_management_name = var.apim_instance.name
  resource_group_name = var.resource_group.name
  versioning_scheme   = "Segment"
}

resource "azurerm_api_management_api" "ehmr_api" {
  name                  = "enterprise-hcl-mod-reg-api"
  display_name          = "Enterprise-wide HCL module registry API"
  api_management_name   = var.apim_instance.name
  resource_group_name   = var.resource_group.name
  path                  = "my-company-hcl-module-registry" # Make sure this matches the root discovery policy hardcoded XML return value
  version_set_id        = azurerm_api_management_api_version_set.ehmr_api_version_set.id
  version               = "v1"
  revision              = "1"
  protocols             = ["https"]
  subscription_required = false
  # As far as the Terraform Module Registry Protocol is concerned, 
  # the most important thing is for the OpenAPI specfile to expose 3 endpoints:
  # 1. List available versions for a specific fully-qualified module
  #     https://developer.hashicorp.com/terraform/internals/module-registry-protocol#list-available-versions-for-a-specific-module
  #     `GET` against `:namespace/:name/:provider/versions`, producing `application/json`
  # 2. Download the source code for a specific module version
  #     https://developer.hashicorp.com/terraform/internals/module-registry-protocol#download-source-code-for-a-specific-module-version
  #     `GET` against `:namespace/:name/:provider/:version/download`, producing `application/json`
  #     whose `X-Terraform-Get` response header is a URL.
  #     That URL, in turn, when requested with `GET`, should return a downloadable binary archive (e.g. `application/gzip`)
  # 3. In our case, let's keep things simple and choose to also use this APIM API to serve the downloadable binary archives themselves.
  #     If this were not an authenticated private HCL module registry, 
  #     something like `https://api.github.com/repos/hashicorp/terraform-aws-consul/tarball/v0.0.1//*?archive=tar.gz` 
  #     could have sufficed, but we want a bit more control, so we will make our own endpoint.
  #     `GET` against `/download/:namespace/:name/:provider/:version/archive` ought to do nicely.
  import {
    content_format = "openapi"
    content_value  = file("${path.module}/files/openapi_schema.yml")
  }
}

resource "azurerm_api_management_api_policy" "ehmr_api_policy_all_operations" {
  # This is how we require Entra auth for all endpoints except the archive download (which will use SAS instead)
  api_name            = azurerm_api_management_api.ehmr_api.name
  api_management_name = var.apim_instance.name
  resource_group_name = var.resource_group.name
  xml_content = templatefile("${path.module}/files/api_policy_for_all_operations.xml.tftpl", {
    entra_tenant_id = data.azurerm_client_config.current_azurerm_config.tenant_id
  })
}
