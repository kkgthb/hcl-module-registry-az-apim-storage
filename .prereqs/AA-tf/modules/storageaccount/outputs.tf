output "storacct_instance" {
  description = "Key details for the storage account instance"
  value = {
    id   = azurerm_storage_account.my_storacct.id
    name = azurerm_storage_account.my_storacct.name
    # TODO:  do we need anything else to bubble up to the outer outputs?
  }
}
