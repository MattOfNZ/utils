#!/usr/bin/env bash

# AWS Parameter Store Prefix Comparison Script
# Usage: ./compare_params.sh [OPTIONS] <source_prefix> <target_prefix>
# Example: ./compare_params.sh /stage/env /prod/env
# Example: ./compare_params.sh --no-decrypt /stage/env /prod/env
#
# Requires: bash 4+, jq


set -euo pipefail

# --- Dependency / version checks ---------------------------------------
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required but not installed. Install it (e.g. 'brew install jq' or 'apt-get install jq')." >&2
    exit 1
fi

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Error: this script requires bash 4+ (associative arrays)." >&2
    echo "On macOS, the default /bin/bash is 3.2 — install a newer bash (e.g. 'brew install bash') and run with that." >&2
    exit 1
fi

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
    if [[ ! "$prefix" =~ ^/ ]]; then
        prefix="/$prefix"
    fi
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

# Temporary files hold raw JSON arrays (one file per prefix)
SOURCE_PARAMS=$(mktemp)
TARGET_PARAMS=$(mktemp)

cleanup() {
    rm -f "$SOURCE_PARAMS" "$TARGET_PARAMS"
}
trap cleanup EXIT

# Function to get parameters and write them as a JSON array: [{Name,Value,Type}, ...]
get_parameters() {
    local prefix="$1"
    local output_file="$2"

    echo "Fetching parameters for prefix: $prefix"
    [ "$VERBOSE" = true ] && echo "  Decryption: $([ "$DECRYPT_VALUES" = true ] && echo "enabled" || echo "disabled")"

    local aws_cmd=(aws ssm get-parameters-by-path --path "$prefix" --recursive)

    if [ "$DECRYPT_VALUES" = true ]; then
        aws_cmd+=(--with-decryption)
        [ "$VERBOSE" = true ] && echo "  Note: SecureString parameters will be decrypted"
    else
        [ "$VERBOSE" = true ] && echo "  Note: SecureString parameters will remain encrypted"
    fi

    aws_cmd+=(--query 'Parameters[*].{Name:Name,Value:Value,Type:Type}' --output json)

    if ! "${aws_cmd[@]}" | jq -c 'sort_by(.Name)' > "$output_file"; then
        echo "Error: Failed to fetch parameters from $prefix" >&2
        if [ "$DECRYPT_VALUES" = true ]; then
            echo "Note: This might be due to insufficient permissions to decrypt SecureString parameters." >&2
            echo "Try running with --no-decrypt flag or ensure you have ssm:GetParameter and kms:Decrypt permissions." >&2
        fi
        exit 1
    fi

    local count
    count=$(jq 'length' "$output_file")
    echo "Found $count parameters in $prefix"

    if [ "$DECRYPT_VALUES" = false ] && [ "$VERBOSE" = true ]; then
        local secure_count
        secure_count=$(jq '[.[] | select(.Type=="SecureString")] | length' "$output_file")
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

# Get parameters from both prefixes
echo
get_parameters "$SOURCE_PREFIX" "$SOURCE_PARAMS"
get_parameters "$TARGET_PREFIX" "$TARGET_PARAMS"

echo
echo "========================================"
echo "ANALYSIS RESULTS"
echo "========================================"

# --- Build target lookup tables, keyed by relative path -----------------
# Using associative arrays (not delimited strings) means no character in
# a value can ever be mistaken for a field separator.
declare -A TGT_VALUE TGT_TYPE

while IFS= read -r line; do
    [ -z "$line" ] && continue
    name=$(jq -r '.Name' <<< "$line")
    value=$(jq -r '.Value' <<< "$line")
    type=$(jq -r '.Type' <<< "$line")
    rel="${name#$TARGET_PREFIX}"
    TGT_VALUE["$rel"]="$value"
    TGT_TYPE["$rel"]="$type"
done < <(jq -c '.[]' "$TARGET_PARAMS")

# --- Result arrays (parallel arrays, one element per record) -----------
declare -a MATCHED_PATH MATCHED_VALUE MATCHED_TYPE
declare -a DIFF_PATH DIFF_SRC_VALUE DIFF_SRC_TYPE DIFF_TGT_VALUE DIFF_TGT_TYPE
declare -a MISSING_PATH MISSING_VALUE MISSING_TYPE

while IFS= read -r line; do
    [ -z "$line" ] && continue
    src_name=$(jq -r '.Name' <<< "$line")
    src_value=$(jq -r '.Value' <<< "$line")
    src_type=$(jq -r '.Type' <<< "$line")
    rel="${src_name#$SOURCE_PREFIX}"

    if [ -v 'TGT_VALUE[$rel]' ]; then
        target_value="${TGT_VALUE[$rel]}"
        target_type="${TGT_TYPE[$rel]}"
        if [ "$src_value" = "$target_value" ] && [ "$src_type" = "$target_type" ]; then
            MATCHED_PATH+=("$rel"); MATCHED_VALUE+=("$src_value"); MATCHED_TYPE+=("$src_type")
        else
            DIFF_PATH+=("$rel"); DIFF_SRC_VALUE+=("$src_value"); DIFF_SRC_TYPE+=("$src_type")
            DIFF_TGT_VALUE+=("$target_value"); DIFF_TGT_TYPE+=("$target_type")
        fi
    else
        MISSING_PATH+=("$rel"); MISSING_VALUE+=("$src_value"); MISSING_TYPE+=("$src_type")
    fi
done < <(jq -c '.[]' "$SOURCE_PARAMS")

# --- Display results ------------------------------------------------------
echo
echo "1. MATCHED ENTRIES (same key, same value, same type):"
echo "---------------------------------------------------"
if [ "${#MATCHED_PATH[@]}" -gt 0 ]; then
    for i in "${!MATCHED_PATH[@]}"; do
        formatted_value=$(format_value_for_display "${MATCHED_VALUE[$i]}" "${MATCHED_TYPE[$i]}")
        echo "  ✓ ${MATCHED_PATH[$i]} = ${formatted_value} (${MATCHED_TYPE[$i]})"
    done
    echo "  Total matched: ${#MATCHED_PATH[@]}"
else
    echo "  No matched parameters found."
fi

echo
echo "2. KEYS WITH DIFFERENT VALUES:"
echo "-----------------------------"
if [ "${#DIFF_PATH[@]}" -gt 0 ]; then
    for i in "${!DIFF_PATH[@]}"; do
        src_formatted=$(format_value_for_display "${DIFF_SRC_VALUE[$i]}" "${DIFF_SRC_TYPE[$i]}")
        target_formatted=$(format_value_for_display "${DIFF_TGT_VALUE[$i]}" "${DIFF_TGT_TYPE[$i]}")
        echo "  ⚠ ${DIFF_PATH[$i]}:"
        echo "    Source: ${src_formatted} (${DIFF_SRC_TYPE[$i]})"
        echo "    Target: ${target_formatted} (${DIFF_TGT_TYPE[$i]})"
    done
    echo "  Total different: ${#DIFF_PATH[@]}"

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
    for i in "${!DIFF_PATH[@]}"; do
        rel_path="${DIFF_PATH[$i]}"
        src_value="${DIFF_SRC_VALUE[$i]}"
        src_type="${DIFF_SRC_TYPE[$i]}"
        target_value="${DIFF_TGT_VALUE[$i]}"
        target_type="${DIFF_TGT_TYPE[$i]}"
        target_param="${TARGET_PREFIX}${rel_path}"
        echo "  # Update: ${rel_path}"
        echo "  # Current target value: $(format_value_for_display "$target_value" "$target_type") (${target_type})"
        echo "  # New value from source: $(format_value_for_display "$src_value" "$src_type") (${src_type})"

        if [ "$DECRYPT_VALUES" = false ] && [ "$src_type" = "SecureString" ]; then
            echo "  # SKIP: Cannot update SecureString with encrypted value"
            echo "  # aws ssm put-parameter --name \"${target_param}\" --value \"ENCRYPTED_VALUE_PLACEHOLDER\" --type \"${src_type}\" --overwrite"
        else
            printf '  aws ssm put-parameter --name %q --value %q --type %q --overwrite\n' "$target_param" "$src_value" "$src_type"
        fi
        echo
    done
else
    echo "  No parameters with different values found."
fi

echo
echo "3. MISSING KEYS IN TARGET:"
echo "-------------------------"
if [ "${#MISSING_PATH[@]}" -gt 0 ]; then
    for i in "${!MISSING_PATH[@]}"; do
        formatted_value=$(format_value_for_display "${MISSING_VALUE[$i]}" "${MISSING_TYPE[$i]}")
        echo "  ✗ Missing: ${MISSING_PATH[$i]} = ${formatted_value} (${MISSING_TYPE[$i]})"
    done
    echo "  Total missing: ${#MISSING_PATH[@]}"

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
    for i in "${!MISSING_PATH[@]}"; do
        rel_path="${MISSING_PATH[$i]}"
        value="${MISSING_VALUE[$i]}"
        param_type="${MISSING_TYPE[$i]}"
        target_param="${TARGET_PREFIX}${rel_path}"
        echo "  # Create: ${rel_path}"

        if [ "$DECRYPT_VALUES" = false ] && [ "$param_type" = "SecureString" ]; then
            echo "  # SKIP: Cannot create SecureString with encrypted value"
            echo "  # aws ssm put-parameter --name \"${target_param}\" --value \"ENCRYPTED_VALUE_PLACEHOLDER\" --type \"${param_type}\""
        else
            printf '  aws ssm put-parameter --name %q --value %q --type %q\n' "$target_param" "$value" "$param_type"
        fi
        echo
    done
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
echo "Matched parameters: ${#MATCHED_PATH[@]}"
echo "Different parameters: ${#DIFF_PATH[@]}"
echo "Missing parameters: ${#MISSING_PATH[@]}"
echo "Total source parameters: $(jq 'length' "$SOURCE_PARAMS")"
echo "Total target parameters: $(jq 'length' "$TARGET_PARAMS")"

if [ "$VERBOSE" = true ]; then
    src_secure=$(jq '[.[] | select(.Type=="SecureString")] | length' "$SOURCE_PARAMS")
    tgt_secure=$(jq '[.[] | select(.Type=="SecureString")] | length' "$TARGET_PARAMS")
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