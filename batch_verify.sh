#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_env() {
    local env_file="$SCRIPT_DIR/.env"
    
    if [[ -f "$env_file" ]]; then
        log_info "Loading environment variables from $env_file"
        
        # Read .env file and export variables
        while IFS='=' read -r key value || [[ -n "$key" ]]; do
            # Skip empty lines and comments
            [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
            
            # Remove leading/trailing whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            
            # Remove quotes if present
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            
            # Export the variable if not already set
            if [[ -z "${!key:-}" ]]; then
                export "$key"="$value"
            fi
        done < "$env_file"
        
        log_success "Environment variables loaded from .env file"
    else
        log_warning ".env file not found at $env_file"
        log_info "You can create a .env file with your configuration variables"
    fi
}

set_defaults() {
    export PUMP_CORE_ADDRESS=${PUMP_CORE_ADDRESS:-""}
    export RPC_URL=${RPC_URL:-""}
    export VERIFICATION_API_URL=${VERIFICATION_API_URL:-""}
    export ETHERSCAN_API_KEY=${ETHERSCAN_API_KEY:-""}
    export CHAIN_ID=${CHAIN_ID:-"1"}
    export FROM_BLOCK=${FROM_BLOCK:-"0"}
    export TO_BLOCK=${TO_BLOCK:-"latest"}
    export FOUNDRY_PROJECT_ROOT=${FOUNDRY_PROJECT_ROOT:-"$SCRIPT_DIR"}
    export VERIFICATION_METHOD=${VERIFICATION_METHOD:-"foundry"}
}

TEMP_DIR="$SCRIPT_DIR/temp"
OUTPUT_DIR="$SCRIPT_DIR/output"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}
log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_requirements() {
    log_info "Checking requirements..."
    
    if ! command -v forge &> /dev/null; then
        log_error "Foundry (forge) is not installed. Please install it first."
        log_info "Install Foundry: curl -L https://foundry.paradigm.xyz | bash && foundryup"
        exit 1
    fi
    
    if ! command -v cast &> /dev/null; then
        log_error "Foundry (cast) is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        log_info "Install jq: sudo apt-get install jq (Ubuntu) or brew install jq (macOS)"
        exit 1
    fi
    
    if [[ -z "$PUMP_CORE_ADDRESS" ]]; then
        log_error "PUMP_CORE_ADDRESS is required. Please set it in .env file or environment variable."
        exit 1
    fi
    
    if [[ -z "$RPC_URL" ]]; then
        log_error "RPC_URL is required. Please set it in .env file or environment variable."
        exit 1
    fi
    
    log_success "All requirements met"
}

setup_directories() {
    mkdir -p "$TEMP_DIR"
    mkdir -p "$OUTPUT_DIR"
}

fetch_creation_events() {
    log_info "Fetching Creation events from block $FROM_BLOCK to $TO_BLOCK..."
    
    local event_signature="Creation(address,address,string,string,string,string,string,uint256)"
    
    # Calculate the keccak256 hash of the event signature
    local topic0=$(cast keccak "$event_signature")
    
    log_info "Using event signature: $event_signature"
    log_info "Using event topic0: $topic0"
    
    # Fetch logs using cast
    cast logs \
        --rpc-url "$RPC_URL" \
        --from-block "$FROM_BLOCK" \
        --to-block "$TO_BLOCK" \
        --address "$PUMP_CORE_ADDRESS" \
        "$topic0" \
        > "$TEMP_DIR/creation_events.yaml" || {
        log_error "Failed to fetch Creation events"
        log_info "Make sure the PumpCore address and RPC URL are correct"
        log_info "Event signature used: $event_signature"
        exit 1
    }

    sed -i '' 's/\t/  /g' /Users/coshi/coshi-cook/contracts-cmswap/temp/creation_events.yaml
    yq -o=json '.' "$TEMP_DIR/creation_events.yaml" > "$TEMP_DIR/creation_events.json"
    local event_count=$(jq length "$TEMP_DIR/creation_events.json")
    log_success "Found $event_count Creation events"
    
    if [[ "$event_count" -eq 0 ]]; then
        log_warning "No events found. Check your configuration and block range."
        log_info "Verify that:"
        log_info "  - PumpCore address is correct: $PUMP_CORE_ADDRESS"
        log_info "  - Block range contains Creation events: $FROM_BLOCK to $TO_BLOCK"
        log_info "  - Event signature matches contract: $event_signature"
        exit 0
    fi
}

parse_events() {
    log_info "Parsing Creation events to extract tokenAddr..."
    
    # For the Creation event: Creation(address indexed creator, address tokenAddr, string logo, string description, string link1, string link2, string link3, uint256 createdTime)
    # - topics[0] = event signature hash
    # - topics[1] = creator (indexed)  
    # - data contains: tokenAddr, logo, description, link1, link2, link3, createdTime
    
    # Extract tokenAddr from event data (first 32 bytes after removing '0x')
    jq -r '.[] | .data' "$TEMP_DIR/creation_events.json" | \
    while read -r data; do
        if [[ -n "$data" && "$data" != "null" ]]; then
            # Remove '0x' prefix
            data_hex="${data#0x}"
            
            # Extract first 32 bytes (64 hex characters) which contains the tokenAddr
            # The tokenAddr is padded to 32 bytes, so we need to extract the last 20 bytes (40 hex chars)
            token_addr_hex="${data_hex:24:40}"  # Skip first 24 chars (12 bytes of padding), take next 40 chars (20 bytes)
            
            # Add '0x' prefix back
            token_addr="0x$token_addr_hex"
            
            echo "$token_addr"
        fi
    done > "$TEMP_DIR/token_addresses_raw.txt"
    
    # Alternative method using cast to decode the data
    log_info "Verifying token addresses using cast decode..."
    
    # Create a temporary file for verified addresses
    > "$TEMP_DIR/token_addresses_verified.txt"
    
    # Process each event to decode properly
    jq -c '.[]' "$TEMP_DIR/creation_events.json" | \
    while read -r event; do
        # Extract the data field
        local event_data=$(echo "$event" | jq -r '.data')
        local block_number=$(echo "$event" | jq -r '.blockNumber')
        local tx_hash=$(echo "$event" | jq -r '.transactionHash')
        
        if [[ -n "$event_data" && "$event_data" != "null" && "$event_data" != "0x" ]]; then
            # Decode the event data using cast
            # The data contains: address tokenAddr, string logo, string description, string link1, string link2, string link3, uint256 createdTime
            local decoded_result
            if decoded_result=$(cast abi-decode "f(address,string,string,string,string,string,uint256)" "$event_data" 2>/dev/null); then
                # Extract just the first element (tokenAddr) from the decoded result
                local token_addr=$(echo "$decoded_result" | head -n1 | xargs)
                
                if [[ "$token_addr" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
                    echo "$token_addr" >> "$TEMP_DIR/token_addresses_verified.txt"
                    log_info "Found token: $token_addr (Block: $block_number, Tx: ${tx_hash:0:10}...)"
                else
                    log_warning "Invalid token address format: $token_addr (Block: $block_number)"
                fi
            else
                log_warning "Failed to decode event data for block $block_number, trying manual extraction..."
                
                # Fallback to manual extraction
                data_hex="${event_data#0x}"
                if [[ ${#data_hex} -ge 64 ]]; then
                    token_addr_hex="${data_hex:24:40}"
                    token_addr="0x$token_addr_hex"
                    
                    if [[ "$token_addr" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
                        echo "$token_addr" >> "$TEMP_DIR/token_addresses_verified.txt"
                        log_info "Extracted token: $token_addr (Block: $block_number, Manual)"
                    fi
                fi
            fi
        else
            log_warning "Empty or null event data in block $block_number"
        fi
    done
    
    # Use the verified addresses file
    if [[ -f "$TEMP_DIR/token_addresses_verified.txt" ]]; then
        # Remove duplicates and empty lines, then sort
        sort -u "$TEMP_DIR/token_addresses_verified.txt" | grep -E '^0x[a-fA-F0-9]{40}$' > "$TEMP_DIR/token_addresses.txt"
        
        local token_count=$(wc -l < "$TEMP_DIR/token_addresses.txt")
        log_success "Extracted $token_count unique valid token addresses"
        
        if [[ "$token_count" -eq 0 ]]; then
            log_error "No valid token addresses extracted. Check the event structure and data format."
            log_info "Sample event data from first event:"
            jq -r '.[0] // empty' "$TEMP_DIR/creation_events.json" | head -5
            exit 1
        fi
        
        # Show first few addresses for verification
        log_info "First few token addresses found:"
        head -5 "$TEMP_DIR/token_addresses.txt" | while read -r addr; do
            log_info "  - $addr"
        done
        
    else
        log_error "Failed to extract any token addresses"
        exit 1
    fi
}

execute_verification() {
    local verify_method=""
    
    case "$VERIFICATION_METHOD" in
        "foundry")
            verify_method="Foundry"
            ;;
    esac
    
    log_info "Executing $verify_method verification..."
    
    local success_count=0
    local failure_count=0
    local results_file="$OUTPUT_DIR/verification_results.txt"
    
    echo "Verification Results - $(date)" > "$results_file"
    echo "Method: $verify_method" >> "$results_file"
    echo "======================================" >> "$results_file"
    
    while read -r token_address; do
        if [[ -n "$token_address" ]]; then
            log_info "Verifying $token_address..."
            
            # Get token details
            local name symbol total_supply
            name=$(cast call "$token_address" "name()(string)" --rpc-url "$RPC_URL" 2>/dev/null || echo "UnknownToken")
            symbol=$(cast call "$token_address" "symbol()(string)" --rpc-url "$RPC_URL" 2>/dev/null || echo "UNK")
            total_supply=$(cast call "$token_address" "totalSupply()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
            
            # Clean up values
            name=$(echo "$name" | sed 's/^"//;s/"$//')
            symbol=$(echo "$symbol" | sed 's/^"//;s/"$//')
            
            local verification_success=false
            
            case "$VERIFICATION_METHOD" in
                "foundry")
                    if forge verify-contract \
                        "$token_address" \
                        "src/ERC20Token.sol:ERC20Token" \
                        --rpc-url "$RPC_URL" \
                        --verifier blockscout \
                        --skip-is-verified-check \
                         --verifier-url "$VERIFICATION_API_URL" \
                        >> "$results_file" 2>&1; then
                        verification_success=true
                    fi
                    ;;
            esac
            
            if $verification_success; then
                log_success "Verified: $token_address ($name)"
                echo "✓ SUCCESS: $token_address ($name - $symbol)" >> "$results_file"
                ((success_count++))
            else
                log_error "Failed to verify: $token_address ($name)"
                echo "✗ FAILED: $token_address ($name - $symbol)" >> "$results_file"
                ((failure_count++))
            fi
            
            # Rate limiting
            sleep 2
        fi
    done < "$TEMP_DIR/token_addresses.txt"
    
    log_success "Verification completed: $success_count successful, $failure_count failed"
    echo "" >> "$results_file"
    echo "Summary: $success_count successful, $failure_count failed" >> "$results_file"
}

generate_report() {
    log_info "Generating summary report..."
    
    local report_file="$OUTPUT_DIR/verification_report.md"
    local total_tokens=$(wc -l < "$TEMP_DIR/token_addresses.txt" 2>/dev/null || echo "0")
    
    cat > "$report_file" << EOF
    # ERC20 Token Verification Report

    **Generated:** $(date)  
    **PumpCore Address:** $PUMP_CORE_ADDRESS  
    **Block Range:** $FROM_BLOCK - $TO_BLOCK  
    **Chain ID:** $CHAIN_ID  
    **Verification Method:** $VERIFICATION_METHOD  

    ## Summary

    - **Total Events Found:** $(jq length "$TEMP_DIR/creation_events.json" 2>/dev/null || echo "0")
    - **Total Tokens Extracted:** $total_tokens
    - **Verification Status:** See verification_results.txt for details

    ## Token Addresses
EOF
    
    if [[ -f "$TEMP_DIR/token_addresses.txt" && -s "$TEMP_DIR/token_addresses.txt" ]]; then
        while read -r token_address; do
            if [[ -n "$token_address" ]]; then
                local name symbol
                name=$(cast call "$token_address" "name()(string)" --rpc-url "$RPC_URL" 2>/dev/null || echo "Unknown")
                symbol=$(cast call "$token_address" "symbol()(string)" --rpc-url "$RPC_URL" 2>/dev/null || echo "UNK")
                
                # Clean up values
                name=$(echo "$name" | sed 's/^"//;s/"$//')
                symbol=$(echo "$symbol" | sed 's/^"//;s/"$//')
                
                echo "- [$token_address](https://etherscan.io/address/$token_address) - $name ($symbol)" >> "$report_file"
            fi
        done < "$TEMP_DIR/token_addresses.txt"
    else
        echo "No token addresses found." >> "$report_file"
    fi
    
    log_success "Report generated: $report_file"
}

main() {
    log_info "Starting batch verification of pump core tokens..."
    
    load_env
    set_defaults
    
    log_info "Configuration:"
    log_info "  PumpCore Address: $PUMP_CORE_ADDRESS"
    log_info "  RPC URL: ${RPC_URL:0:50}..."
    log_info "  Chain ID: $CHAIN_ID"
    log_info "  Block Range: $FROM_BLOCK to $TO_BLOCK"
    log_info "  Verification Method: $VERIFICATION_METHOD"
    
    check_requirements
    setup_directories
    
    fetch_creation_events
    parse_events
    
    if [[ "$1" == "--verify" ]]; then
        execute_verification
    fi
    
    generate_report
    
    log_success "Batch verification process completed!"
    
    if [[ "$1" == "--verify" ]]; then
        log_info "  - Verification results: $OUTPUT_DIR/verification_results.txt"
    fi
}

case "${1:-}" in
    *)
        main "$@"
        ;;
esac
