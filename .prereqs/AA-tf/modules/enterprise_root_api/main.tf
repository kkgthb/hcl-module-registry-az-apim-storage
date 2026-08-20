resource "azurerm_api_management_api" "enterprise_root_api" {
  name                  = "enterprise-root-api"
  display_name          = "Enterprise-wide root API"
  api_management_name   = var.apim_instance.name
  resource_group_name   = var.resource_group.name
  revision              = "1"
  protocols             = ["https"]
  subscription_required = false
  # As far as the Terraform Module Registry Protocol is concerned, 
  # the most important thing is to 
  # expose 1 endpoint:  `GET` against `/.well-known/terraform.json`.
  # https://developer.hashicorp.com/terraform/internals/remote-service-discovery#discovery-process
  # (Of course, your OpenAPI specification might need to have additional "root"-level 
  # endpoints that support unrelated things, like other protocols from other vendors.)
  import {
    content_format = "openapi"
    content_value  = file("${path.module}/files/openapi_schema.yml")
  }
}

resource "azurerm_api_management_api_operation_policy" "op_pol_get_well_known_tf_json" {
  operation_id        = "get-wellknown-terraformjson" # Make sure this spelling matches an appropriate `operationId` from the OpenAPI schema above
  api_name            = azurerm_api_management_api.enterprise_root_api.name
  api_management_name = var.apim_instance.name
  resource_group_name = var.resource_group.name
  xml_content         = file("${path.module}/files/operation_policy_get_well_known_terraform_json.xml")
  depends_on          = [azurerm_api_management_api.enterprise_root_api]
}
