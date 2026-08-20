output "storacct_container_name" {
  description = "Name of the blob container used to store the enterprise-wide HCL module registry archives."
  value       = azurerm_storage_container.enterprise_hcl_mod_reg_storacct_container.name
}
