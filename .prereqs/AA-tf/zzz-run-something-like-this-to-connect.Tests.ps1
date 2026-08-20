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

    $script:ResourceGroupName = $script:TfOutputs.resource_group_name.value
    if ([string]::IsNullOrWhiteSpace($script:ResourceGroupName)) {
        throw "Terraform output 'resource_group_name' was empty. Have you run zzz-run-something-like-this-to-apply.ps1 yet?"
    }

    $script:StoracctName = $script:TfOutputs.storacct_name.value
    if ([string]::IsNullOrWhiteSpace($script:StoracctName)) {
        throw "Terraform output 'storacct_name' was empty. Have you run zzz-run-something-like-this-to-apply.ps1 yet?"
    }

    $script:HclModRegContainerName = $script:TfOutputs.hcl_mod_reg_container_name.value
    if ([string]::IsNullOrWhiteSpace($script:HclModRegContainerName)) {
        throw "Terraform output 'hcl_mod_reg_container_name' was empty. Have you run zzz-run-something-like-this-to-apply.ps1 yet?"
    }

    # Azure API Management's default (non-custom-domain) gateway hostname format.
    $script:ApimGatewayBaseUrl = "https://$($script:ApimName).azure-api.net"
    $script:WellKnownTerraformJsonUrl = "$($script:ApimGatewayBaseUrl)/.well-known/terraform.json"
    Write-Host "Well-known enterprise root terraform.json URL is $script:WellKnownTerraformJsonUrl"

}

Describe "enterprise_hcl_mod_reg_api module: HCL module registry blob container" {

    BeforeAll {
        # Requires the caller to already be logged into the Azure CLI (see zzz-run-something-like-this-to-apply.ps1)
        # with a principal that was granted the Storage Blob Data Contributor role assignment in main.tf.
        # It will seem to no-op and hang if you are not logged in, because Pester will not surface the reminder that you are not logged in.
        $rawBlobList = az storage blob list `
            --account-name $script:StoracctName `
            --container-name $script:HclModRegContainerName `
            --auth-mode 'login' `
            --output 'json' 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "``az storage blob list`` failed against container '$script:HclModRegContainerName' in storage account '$script:StoracctName': $rawBlobList"
        }
        $script:HclModRegBlobs = $rawBlobList | ConvertFrom-Json
    }

    # For future fixes:  this is a little sloppy, since it doesn't validate whether the container even exists before moving on to this test, but whatevs, for now.
    It "contains 0 files, since no modules have been published to the registry yet" {
        @($script:HclModRegBlobs).Count | Should -Be 0
    }
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

Describe "enterprise_hcl_mod_reg_api module: data-plane list-versions endpoint" {

    BeforeAll {
        $script:ListVersionsUrl = "$($script:ApimGatewayBaseUrl)/my-company-hcl-module-registry/v1/hashicorp/consul/aws/versions"
        Write-Host "List Versions URL is $script:ListVersionsUrl"
    }

    BeforeEach {
        $script:ListVersionsResponse = Invoke-WebRequest -Uri $script:ListVersionsUrl -Method 'Get' -SkipHttpErrorCheck -UseBasicParsing
    }

    It "requires bearer auth and rejects anonymous requests with HTTP 401" {
        $script:ListVersionsResponse.StatusCode | Should -Be 401
    }

    It "returns the APIM JWT validation error message for anonymous requests" {
        $script:ListVersionsResponse.Content | Should -Match 'Unauthorized\. Access token is missing or invalid\.'
    }

    It "is still routed through APIM (not a missing route)" {
        $script:ListVersionsResponse.StatusCode | Should -Not -Be 404
    }
}

Describe "enterprise_hcl_mod_reg_api module: data-plane list-versions endpoint with caller auth" {

    BeforeAll {
        $script:ListVersionsUrl = "$($script:ApimGatewayBaseUrl)/my-company-hcl-module-registry/v1/hashicorp/consul/aws/versions"
        $script:CanRunAuthenticatedListVersionsTest = $false
        $script:AuthListVersionsSkipReason = ""
        $script:HasApiAudienceToken = $false

        $rawAzAccount = az account show --output json 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rawAzAccount)) {
            $script:AuthListVersionsSkipReason = "Azure CLI is not logged in. Run 'az login' first."
        }
        else {
            # Prefer an OAuth2 v2 token because the APIM policy uses the v2.0 OpenID metadata endpoint.
            $rawAccessToken = az account get-access-token --scope "https://management.azure.com/.default" --output json 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rawAccessToken)) {
                $rawAccessToken = az account get-access-token --resource "https://management.azure.com/" --output json 2>$null
            }

            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rawAccessToken)) {
                $script:AuthListVersionsSkipReason = "Could not acquire access token from Azure CLI."
            }
            else {
                $tokenPayload = $rawAccessToken | ConvertFrom-Json
                if ([string]::IsNullOrWhiteSpace($tokenPayload.accessToken)) {
                    $script:AuthListVersionsSkipReason = "Azure CLI returned an empty access token."
                }
                else {
                    $script:ArmBearerToken = $tokenPayload.accessToken
                    $script:CanRunAuthenticatedListVersionsTest = $true

                    # Optional: if APIM_TEST_TOKEN_SCOPE is set, try to get a token with an API-specific audience.
                    # Example values: api://<app-id>/.default or <application-id-uri>/.default
                    if (-not [string]::IsNullOrWhiteSpace($env:APIM_TEST_TOKEN_SCOPE)) {
                        $rawScopedToken = az account get-access-token --scope $env:APIM_TEST_TOKEN_SCOPE --output json 2>$null
                        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($rawScopedToken)) {
                            $scopedTokenPayload = $rawScopedToken | ConvertFrom-Json
                            if (-not [string]::IsNullOrWhiteSpace($scopedTokenPayload.accessToken)) {
                                $script:ApiAudienceBearerToken = $scopedTokenPayload.accessToken
                                $script:HasApiAudienceToken = $true
                            }
                        }
                    }
                }
            }
        }
    }

    BeforeEach {
        if ($script:CanRunAuthenticatedListVersionsTest) {
            $script:ArmTokenListVersionsResponse = Invoke-WebRequest -Uri $script:ListVersionsUrl -Method 'Get' -Headers @{ Authorization = "Bearer $($script:ArmBearerToken)" } -SkipHttpErrorCheck -UseBasicParsing
        }

        if ($script:HasApiAudienceToken) {
            $script:ApiAudienceTokenListVersionsResponse = Invoke-WebRequest -Uri $script:ListVersionsUrl -Method 'Get' -Headers @{ Authorization = "Bearer $($script:ApiAudienceBearerToken)" } -SkipHttpErrorCheck -UseBasicParsing
        }
    }

    It "rejects ARM-audience token for this API (expected when audience does not match)" {
        if (-not $script:CanRunAuthenticatedListVersionsTest) {
            Set-ItResult -Skipped -Because $script:AuthListVersionsSkipReason
            return
        }

        $script:ArmTokenListVersionsResponse.StatusCode | Should -Be 401
        $script:ArmTokenListVersionsResponse.Content | Should -Match 'Unauthorized\. Access token is missing or invalid\.'
    }

    It "accepts API-audience token when APIM_TEST_TOKEN_SCOPE is provided" {
        if (-not $script:CanRunAuthenticatedListVersionsTest) {
            Set-ItResult -Skipped -Because $script:AuthListVersionsSkipReason
            return
        }

        if (-not $script:HasApiAudienceToken) {
            Set-ItResult -Skipped -Because "Set APIM_TEST_TOKEN_SCOPE to your API audience scope to run this test."
            return
        }

        $script:ApiAudienceTokenListVersionsResponse.StatusCode | Should -Not -Be 401
        $script:ApiAudienceTokenListVersionsResponse.StatusCode | Should -Not -Be 403
        $script:ApiAudienceTokenListVersionsResponse.StatusCode | Should -Not -Be 404
    }
}

