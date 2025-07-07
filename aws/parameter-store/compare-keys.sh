#!/bin/bash

# AWS Parameter Store Prefix Comparison Script
# Usage: ./compare_params.sh [OPTIONS] <source_prefix> <target_prefix>
# Example: ./compare_params.sh /stage/env /prod/env
# Example: ./compare_params.sh --no-decrypt /stage/env /prod/env

set -euo pipefail

# Default options
DECRYPT_VALUES=true
VERBOSE=false

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS] <source_prefix> <target_prefix>"
    echo ""
    echo "Options:"
    echo "  --no-decrypt    Don't decrypt SecureString parameters (show encrypted values)"
    echo "  --decrypt       Decrypt SecureString parameters (default)"
    echo "  --verbose       Show detailed processing information"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 /stage/env /prod/env"
    echo "  $0 /stage/env/ /prod/env/"
    echo "  $0 --no-decrypt /stage/env /prod/env"
    echo "  $0 --verbose /stage/env /prod/env"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-decrypt)
            DECRYPT_VALUES=false
            shift
            ;;
        --decrypt)
            DECRYPT_VALUES=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        -*)
            echo "Unknown option $1"
            usage
            ;;
        *)
            break
            ;;
    esac
done

# Check if correct number of arguments remain
if [ $# -ne 2 ]; then
    usage
fi

SOURCE_PREFIX="$1"
TARGET_PREFIX="$2"

# Normalize prefixes (ensure they start with / and don't end with /)
normalize_prefix() {
    local prefix="$1"
    # Add leading slash if missing
    if [[ ! "$prefix" =~ ^/ ]]; then
        prefix="/$prefix"
    fi
    # Remove trailing slash if present
    prefix="${prefix%/}"
    echo "$prefix"
}

SOURCE_PREFIX=$(normalize_prefix "$SOURCE_PREFIX")
TARGET_PREFIX=$(normalize_prefix "$TARGET_PREFIX")

echo "Comparing Parameter Store prefixes:"
echo "Source: $SOURCE_PREFIX"
echo "Target: $TARGET_PREFIX"
echo "Decryption: $([ "$DECRYPT_VALUES" = true ] && echo "ENABLED" || echo "DISABLED")"
echo "========================================"

# Temporary files for processing
SOURCE_PARAMS=$(mktemp)
TARGET_PARAMS=$(mktemp)
MATCHED_PARAMS=$(mktemp)
DIFFERENT_PARAMS=$(mktemp)
MISSING_PARAMS=$(mktemp)

# Cleanup function
cleanup() {
    rm -f "$SOURCE_PARAMS" "$TARGET_PARAMS" "$MATCHED_PARAMS" "$DIFFERENT_PARAMS" "$MISSING_PARAMS"
}
trap cleanup EXIT

# Function to get parameters and format them as "name|value|type"
get_parameters() {
    local prefix="$1"
    local output_file="$2"
    
    echo "Fetching parameters for prefix: $prefix"
    [ "$VERBOSE" = true ] && echo "  Decryption: $([ "$DECRYPT_VALUES" = true ] && echo "enabled" || echo "disabled")"
    
    # Build AWS CLI command based on decryption setting
    local aws_cmd="aws ssm get-parameters-by-path --path \"$prefix\" --recursive"
    
    if [ "$DECRYPT_VALUES" = true ]; then
        aws_cmd="$aws_cmd --with-decryption"
        [ "$VERBOSE" = true ] && echo "  Note: SecureString parameters will be decrypted"
    else
        [ "$VERBOSE" = true ] && echo "  Note: SecureString parameters will remain encrypted"
    fi
    
    aws_cmd="$aws_cmd --query 'Parameters[*].[Name,Value,Type]' --output text"
    
    # Execute command with error handling
    if ! eval "$aws_cmd" | sort > "$output_file"; then
        echo "Error: Failed to fetch parameters from $prefix" >&2
        if [ "$DECRYPT_VALUES" = true ]; then
            echo "Note: This might be due to insufficient permissions to decrypt SecureString parameters." >&2
            echo "Try running with --no-decrypt flag or ensure you have ssm:GetParameter and kms:Decrypt permissions." >&2
        fi
        exit 1
    fi
    
    local count=$(wc -l < "$output_file")
    echo "Found $count parameters in $prefix"
    
    # Count encrypted parameters if decryption is disabled
    if [ "$DECRYPT_VALUES" = false ] && [ "$VERBOSE" = true ]; then
        local secure_count=$(awk -F'\t' '$3=="SecureString"' "$output_file" | wc -l)
        [ "$secure_count" -gt 0 ] && echo "  ($secure_count SecureString parameters not decrypted)"
    fi
}

# Function to format value for display
format_value_for_display() {
    local value="$1"
    local param_type="$2"
    
    if [ "$param_type" = "SecureString" ] && [ "$DECRYPT_VALUES" = false ]; then
        echo "${value} [ENCRYPTED]"
    elif [ "$param_type" = "SecureString" ] && [ "$DECRYPT_VALUES" = true ]; then
        echo "${value} [DECRYPTED]"
    else
        echo "${value}"
    fi
}
get_relative_path() {
    local full_path="$1"
    local prefix="$2"
    echo "${full_path#$prefix}"
}

# Get parameters from both prefixes
echo
get_parameters "$SOURCE_PREFIX" "$SOURCE_PARAMS"
get_parameters "$TARGET_PREFIX" "$TARGET_PARAMS"

echo
echo "========================================"
echo "ANALYSIS RESULTS"
echo "========================================"

# Process parameters and compare
while IFS=$'\t' read -r src_name src_value src_type; do
    if [ -z "$src_name" ]; then continue; fi
    
    relative_path=$(get_relative_path "$src_name" "$SOURCE_PREFIX")
    target_name="${TARGET_PREFIX}${relative_path}"
    
    # Look for corresponding parameter in target
    target_line=$(grep "^${target_name}$(printf '\t')" "$TARGET_PARAMS" || echo "")
    
    if [ -n "$target_line" ]; then
        # Parameter exists in target
        target_value=$(echo "$target_line" | cut -f2)
        target_type=$(echo "$target_line" | cut -f3)
        
        if [ "$src_value" = "$target_value" ] && [ "$src_type" = "$target_type" ]; then
            # Values and types match
            echo "$relative_path|$src_value|$src_type" >> "$MATCHED_PARAMS"
        else
            # Values or types differ
            echo "$relative_path|$src_value|$src_type|$target_value|$target_type" >> "$DIFFERENT_PARAMS"
        fi
    else
        # Parameter missing in target
        echo "$relative_path|$src_value|$src_type" >> "$MISSING_PARAMS"
    fi
done < "$SOURCE_PARAMS"

# Display results
echo
echo "1. MATCHED ENTRIES (same key, same value, same type):"
echo "---------------------------------------------------"
if [ -s "$MATCHED_PARAMS" ]; then
    while IFS='|' read -r rel_path value param_type; do
        formatted_value=$(format_value_for_display "$value" "$param_type")
        echo "  ✓ ${rel_path} = ${formatted_value} (${param_type})"
    done < "$MATCHED_PARAMS"
    echo "  Total matched: $(wc -l < "$MATCHED_PARAMS")"
else
    echo "  No matched parameters found."
fi

echo
echo "2. KEYS WITH DIFFERENT VALUES:"
echo "-----------------------------"
if [ -s "$DIFFERENT_PARAMS" ]; then
    while IFS='|' read -r rel_path src_value src_type target_value target_type; do
        src_formatted=$(format_value_for_display "$src_value" "$src_type")
        target_formatted=$(format_value_for_display "$target_value" "$target_type")
        echo "  ⚠ ${rel_path}:"
        echo "    Source: ${src_formatted} (${src_type})"
        echo "    Target: ${target_formatted} (${target_type})"
    done < "$DIFFERENT_PARAMS"
    echo "  Total different: $(wc -l < "$DIFFERENT_PARAMS")"
    
    echo
    echo "  UPDATE SCRIPT FOR DIFFERENT VALUES:"
    echo "  -----------------------------------"
    echo "  #!/bin/bash"
    echo "  # Script to update different values from $SOURCE_PREFIX to $TARGET_PREFIX"
    if [ "$DECRYPT_VALUES" = false ]; then
        echo "  # WARNING: Script generated with --no-decrypt flag"
        echo "  # SecureString values shown are encrypted and cannot be used directly"
        echo "  # Re-run with --decrypt flag to get usable values"
    fi
    echo "  set -euo pipefail"
    echo
    while IFS='|' read -r rel_path src_value src_type target_value target_type; do
        target_param="${TARGET_PREFIX}${rel_path}"
        echo "  # Update: ${rel_path}"
        echo "  # Current target value: $(format_value_for_display "$target_value" "$target_type") (${target_type})"
        echo "  # New value from source: $(format_value_for_display "$src_value" "$src_type") (${src_type})"
        
        if [ "$DECRYPT_VALUES" = false ] && [ "$src_type" = "SecureString" ]; then
            echo "  # SKIP: Cannot update SecureString with encrypted value"
            echo "  # aws ssm put-parameter --name \"${target_param}\" --value \"ENCRYPTED_VALUE_PLACEHOLDER\" --type \"${src_type}\" --overwrite"
        else
            echo "  aws ssm put-parameter --name \"${target_param}\" --value \"${src_value}\" --type \"${src_type}\" --overwrite"
        fi
        echo
    done < "$DIFFERENT_PARAMS"
else
    echo "  No parameters with different values found."
fi

echo
echo "3. MISSING KEYS IN TARGET:"
echo "-------------------------"
if [ -s "$MISSING_PARAMS" ]; then
    while IFS='|' read -r rel_path value param_type; do
        formatted_value=$(format_value_for_display "$value" "$param_type")
        echo "  ✗ Missing: ${rel_path} = ${formatted_value} (${param_type})"
    done < "$MISSING_PARAMS"
    echo "  Total missing: $(wc -l < "$MISSING_PARAMS")"
    
    echo
    echo "  UPDATE SCRIPT FOR MISSING KEYS:"
    echo "  -------------------------------"
    echo "  #!/bin/bash"
    echo "  # Script to create missing parameters from $SOURCE_PREFIX to $TARGET_PREFIX"
    if [ "$DECRYPT_VALUES" = false ]; then
        echo "  # WARNING: Script generated with --no-decrypt flag"
        echo "  # SecureString values shown are encrypted and cannot be used directly"
        echo "  # Re-run with --decrypt flag to get usable values"
    fi
    echo "  set -euo pipefail"
    echo
    while IFS='|' read -r rel_path value param_type; do
        target_param="${TARGET_PREFIX}${rel_path}"
        echo "  # Create: ${rel_path}"
        
        if [ "$DECRYPT_VALUES" = false ] && [ "$param_type" = "SecureString" ]; then
            echo "  # SKIP: Cannot create SecureString with encrypted value"
            echo "  # aws ssm put-parameter --name \"${target_param}\" --value \"ENCRYPTED_VALUE_PLACEHOLDER\" --type \"${param_type}\""
        else
            echo "  aws ssm put-parameter --name \"${target_param}\" --value \"${value}\" --type \"${param_type}\""
        fi
        echo
    done < "$MISSING_PARAMS"
else
    echo "  No missing parameters found."
fi

echo
echo "========================================"
echo "SUMMARY"
echo "========================================"
echo "Source prefix: $SOURCE_PREFIX"
echo "Target prefix: $TARGET_PREFIX"
echo "Decryption mode: $([ "$DECRYPT_VALUES" = true ] && echo "ENABLED" || echo "DISABLED")"
echo "Matched parameters: $([ -s "$MATCHED_PARAMS" ] && wc -l < "$MATCHED_PARAMS" || echo "0")"
echo "Different parameters: $([ -s "$DIFFERENT_PARAMS" ] && wc -l < "$DIFFERENT_PARAMS" || echo "0")"
echo "Missing parameters: $([ -s "$MISSING_PARAMS" ] && wc -l < "$MISSING_PARAMS" || echo "0")"
echo "Total source parameters: $(wc -l < "$SOURCE_PARAMS")"
echo "Total target parameters: $(wc -l < "$TARGET_PARAMS")"

# Count SecureString parameters
if [ "$VERBOSE" = true ]; then
    src_secure=$(awk -F'\t' '$3=="SecureString"' "$SOURCE_PARAMS" | wc -l)
    tgt_secure=$(awk -F'\t' '$3=="SecureString"' "$TARGET_PARAMS" | wc -l)
    echo "SecureString parameters in source: $src_secure"
    echo "SecureString parameters in target: $tgt_secure"
fi

echo
if [ "$DECRYPT_VALUES" = false ]; then
    echo "⚠️  WARNING: Decryption was disabled!"
    echo "   - SecureString parameter values are shown encrypted"
    echo "   - Generated update scripts will not work for SecureString parameters"
    echo "   - Re-run with --decrypt flag to get usable values"
    echo
fi

echo "Note: Review all generated scripts carefully before execution!"
echo "Consider testing in a non-production environment first."

if [ "$DECRYPT_VALUES" = true ]; then
    echo
    echo "🔓 Decryption enabled: All parameter values have been decrypted for comparison."
    echo "   Ensure your AWS credentials have the necessary KMS decrypt permissions."
fi

