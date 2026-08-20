variable "workload_nickname" {
  type     = string
  nullable = false
}

variable "resource_group" {
  description = "Parent resource group parameters"
  type = object({
    id       = string
    name     = string
    location = string
  })
  nullable = false
}

variable "storacct_instance" {
  description = "Key details about the parent storage account instance to attach the child blob containers to."
  type = object({
    id   = string
    name = string
  })
}

variable "apim_instance" {
  description = "Key details of the parent APIM instance to attach the child APIs to."
  type = object({
    id                 = string
    name               = string
    management_api_url = string
  })
  nullable = false
}
