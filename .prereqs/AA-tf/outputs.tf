output "resource_group_name" {
  value = azurerm_resource_group.my_resource_group.name
}

output "apim_name" {
  value = module.apimanagement.apim_instance.name
}

output "storacct_name" {
  value = module.storageaccount.storacct_instance.name
}

output "hcl_mod_reg_container_name" {
  value = module.enterprise_hcl_module_registry_storcont_and_apimapi.storacct_container_name
}