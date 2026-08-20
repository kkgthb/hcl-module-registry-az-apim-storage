# LLM-generated, can't claim credit.  Looks pretty decent, though.
<#
.SYNOPSIS
Pester test that validates the `GET /.well-known/terraform.json` operation exposed by the
`enterprise_root_api` Terraform module (modules/enterprise_root_api/main.tf) actually behaves
the way the Terraform Remote Service Discovery protocol expects.
https://developer.hashicorp.com/terraform/internals/remote-service-discovery#discovery-process

.DESCRIPTION
Assumes you've already run `terraform apply` (see zzz-run-something-like-this-to-apply.ps1)
against this root module, so that a real Azure API Management instance + API exist to call.

Run with:
    Invoke-Pester -Path .\zzz-run-something-like-this-to-connect.Tests.ps1 -Output Detailed
#>

BeforeAll {
    Push-Location("$PsScriptRoot")
    try {
        $rawOutputs = terraform output -json 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rawOutputs)) {
            throw "``terraform output -json`` failed. Have you run zzz-run-something-like-this-to-apply.ps1 yet?"
        }
        $script:TfOutputs = $rawOutputs | ConvertFrom-Json
    }
    finally {
        Pop-Location
    }

    $script:ApimName = $script:TfOutputs.apim_name.value
    if ([string]::IsNullOrWhiteSpace($script:ApimName)) {
        throw "Terraform output 'apim_name' was empty. Have you run zzz-run-something-like-this-to-apply.ps1 yet?"
    }

    # Azure API Management's default (non-custom-domain) gateway hostname format.
    $script:ApimGatewayBaseUrl = "https://$($script:ApimName).azure-api.net"
    $script:WellKnownTerraformJsonUrl = "$($script:ApimGatewayBaseUrl)/.well-known/terraform.json"
    Write-Host "Well-known enterprise root terraform.json URL is $script:WellKnownTerraformJsonUrl"
}

Describe "enterprise_root_api module: GET /.well-known/terraform.json" {

    BeforeEach {
        $script:Response = Invoke-WebRequest -Uri $script:WellKnownTerraformJsonUrl -Method 'Get' -SkipHttpErrorCheck -UseBasicParsing
    }

    It "does not require a subscription key (subscription_required = false in main.tf)" {
        $script:Response.StatusCode | Should -Not -Be 401
        $script:Response.StatusCode | Should -Not -Be 403
    }

    It "responds to an anonymous GET request with HTTP 200" {
        $script:Response.StatusCode | Should -Be 200
    }

    It "responds with a JSON content type" {
        $script:Response.Headers['Content-Type'] | Should -Match 'application/json'
    }

    It "responds with a body that is valid JSON" {
        { $script:Response.Content | ConvertFrom-Json -ErrorAction 'Stop' } | Should -Not -Throw
    }

    It "exposes the 'modules.v1' service key required by the Terraform Remote Service Discovery protocol" {
        $body = $script:Response.Content | ConvertFrom-Json
        $body.PSObject.Properties.Name | Should -Contain 'modules.v1'
    }

    It "returns the module registry base path configured in the operation policy" {
        # See modules/enterprise_root_api/files/operation_policy_get_well_known_terraform_json.xml
        $body = $script:Response.Content | ConvertFrom-Json
        $body.'modules.v1' | Should -Be '/my-company-hcl-module-registry/v1/'
    }
}
