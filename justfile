# Import .env file. Read the README.md for more informations.
set dotenv-load

# This justfile has been tested on linux, specifically on the dev container. Should there be any problems with its 
# use on other operating systems, please adjust the justfile accordingly using just attributes.
# Ref: https://github.com/casey/just?tab=readme-ov-file#enabling-and-disabling-recipes180

app := "imsub"
aws_profile  := env_var("AWS_PROFILE")
environment  := env("APP_ENVIRONMENT", "dev")
prefix := app + "-" + environment 
# Set the relative path from the root to the current directory as the default_module.
current_folder := shell('realpath --relative-to="' + justfile_directory() + '" "' + invocation_directory() + '"')


# List the recipes
@default:
    just --list

# Remove all tmps file
@clean:
    echo "Cleaning all .tmp directories..."
    find . -type d -name ".tmp" -exec rm -rf {} + 
    echo "All .tmp directories have been removed"


[group('deployment')]
bootstrap:
    #!/usr/bin/env bash
    set -euxo pipefail
    cd {{justfile_directory()}}/bootstrap 
    terraform init -var="aws_profile={{ aws_profile }}"
    terraform apply -var="aws_profile={{ aws_profile }}"

# Terraform initialization
[group('deployment')]
init module *FLAGS:
    #!/usr/bin/env bash
    set -euxo pipefail
    module='{{ if module == "." { current_folder } else { module } }}'
    module_key='{{ if module == "." { trim_end_match(replace(current_folder, "/", "-"), "-") } else { trim_end_match(replace(module, "/", "-"), "-") } }}'
    cd {{justfile_directory()}}/$module 
    terraform init \
        -backend-config="bucket={{ app }}-terraform-state" \
        -backend-config="dynamodb_table={{ app }}-terraform-state" \
        -backend-config="key={{ prefix }}-$module_key.tfstate" \
        {{ FLAGS }}

# Plan the module changes
[group('deployment')]
plan module *FLAGS:
    #!/usr/bin/env bash
    set -euxo pipefail
    module='{{ if module == "." { current_folder } else { module } }}'
    cd {{justfile_directory()}}/$module 
    terraform plan \
        -var="environment={{ environment }}" \
        -var="aws_profile={{ aws_profile }}" \
        {{ FLAGS }}

# Apply the module changes
[group('deployment')]
apply module *FLAGS:
    #!/usr/bin/env bash
    set -euxo pipefail
    module='{{ if module == "." { current_folder } else { module } }}'
    cd {{justfile_directory()}}/$module 
    terraform apply \
        -var='environment={{ environment }}' \
        -var="aws_profile={{ aws_profile }}" \
        {{ FLAGS }}

# Destroy the module
[group('deployment')]
destroy module *FLAGS:
    #!/usr/bin/env bash
    set -euxo pipefail
    module='{{ if module == "." { current_folder } else { module } }}'
    cd {{justfile_directory()}}/$module 
    terraform destroy \
        -var="environment={{ environment }}" \
        -var="aws_profile={{ aws_profile }}" \
        {{ FLAGS }}

# Format the module with Terraform
[group('check')]
fmt module *FLAGS:
    #!/usr/bin/env bash
    set -euxo pipefail
    module='{{ if module == "." { current_folder } else { module } }}'
    cd {{justfile_directory()}}/$module 
    terraform fmt -recursive {{ FLAGS }}

# Validate the module
[group('check')]
validate module *FLAGS:
    #!/usr/bin/env bash
    set -euxo pipefail
    module='{{ if module == "." { current_folder } else { module } }}'
    cd {{justfile_directory()}}/$module 
    terraform validate {{ FLAGS }}

# Lint checks for the module
[group('check')]
lint module *FLAGS:
    #!/usr/bin/env bash
    set -euxo pipefail
    module='{{ if module == "." { current_folder } else { module } }}'
    cd {{justfile_directory()}}/$module 
    tflint -f compact --recursive {{ FLAGS }}

# Finds spelling mistakes among source code
[group('check')]
typos module *FLAGS:
    #!/usr/bin/env bash
    set -euxo pipefail
    module='{{ if module == "." { current_folder } else { module } }}'
    cd {{justfile_directory()}}/$module 
    typos {{ FLAGS }}

# Security checks for the module using tfsec
[group('security')]
tfsec module *FLAGS:
    #!/usr/bin/env bash
    set -euxo pipefail
    module='{{ if module == "." { current_folder } else { module } }}'
    cd {{justfile_directory()}}/$module 
    tfsec --no-code {{ FLAGS }}

# Security checks for the module using checkov
[group('security')]
checkov module *FLAGS:
    #!/usr/bin/env bash
    set -euxo pipefail
    module='{{ if module == "." { current_folder } else { module } }}'
    cd {{justfile_directory()}}/$module 
    checkov -d . --compact {{ FLAGS }}

# Security checks for the module using terrascan
[group('security')]
terrascan module *FLAGS:
    #!/usr/bin/env bash
    set -euxo pipefail
    module='{{ if module == "." { current_folder } else { module } }}'
    cd {{justfile_directory()}}/$module 
    terrascan scan {{ FLAGS }}


# Aliases for frequently used commands
[private]
alias f := fmt
[private]
alias p := plan
[private]
alias a := apply
[private]
alias d := destroy
[private]
alias v := validate