#!/bin/bash

set -euo pipefail

# OCI Registry Cleanup Script
# This script removes OCI artifacts from a registry based on age and filter criteria
# Can be run as: standalone script, CI/CD pipeline, or Kubernetes CronJob

# Configuration via environment variables with defaults
REGISTRY_URL="${REGISTRY_URL:-}"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-}"
ARTIFACT_FILTER="${ARTIFACT_FILTER:-}"     # Comma-separated list of prefixes (e.g., "car-service,api-gateway") or regex pattern
TAG_FILTER="${TAG_FILTER:-}"               # Regex pattern to match image tags (e.g., "^master-.*" or ".*-snapshot$")
RETENTION_DAYS="${RETENTION_DAYS:-30}"     # Delete artifacts older than this
DRY_RUN="${DRY_RUN:-true}"                 # Set to 'true' to see what would be deleted
BATCH_SIZE="${BATCH_SIZE:-10}"             # Number of artifacts to process in parallel
LOG_LEVEL="${LOG_LEVEL:-INFO}"             # DEBUG, INFO, WARN, ERROR

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_debug() {
    [[ "$LOG_LEVEL" == "DEBUG" ]] && echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_info() {
    [[ "$LOG_LEVEL" =~ ^(DEBUG|INFO)$ ]] && echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_warn() {
    [[ "$LOG_LEVEL" =~ ^(DEBUG|INFO|WARN)$ ]] && echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Function to check if repository matches filter
matches_filter() {
    local repo=$1
    local filter="$ARTIFACT_FILTER"
    
    # If no filter specified, match everything
    if [[ -z "$filter" ]]; then
        return 0
    fi
    
    # Check if filter contains comma (prefix list) or looks like regex
    if [[ "$filter" == *,* ]]; then
        # Treat as comma-separated list of prefixes
        log_debug "Using prefix matching mode"
        IFS=',' read -ra prefixes <<< "$filter"
        for prefix in "${prefixes[@]}"; do
            # Trim whitespace
            prefix="$(echo -e "${prefix}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            if [[ "$repo" == "$prefix"* ]]; then
                log_debug "Repository '$repo' matches prefix '$prefix'"
                return 0
            fi
        done
        log_debug "Repository '$repo' does not match any prefix"
        return 1
    else
        # Treat as regex pattern
        log_debug "Using regex matching mode"
        if echo "$repo" | grep -qE "$filter"; then
            log_debug "Repository '$repo' matches regex '$filter'"
            return 0
        else
            log_debug "Repository '$repo' does not match regex '$filter'"
            return 1
        fi
    fi
}

# Function to check if tag matches filter
matches_tag_filter() {
    local tag=$1
    local filter="$TAG_FILTER"
    
    # If no filter specified, match everything
    if [[ -z "$filter" ]]; then
        return 0
    fi
    
    # Treat as regex pattern
    log_debug "Checking if tag '$tag' matches regex '$filter'"
    if echo "$tag" | grep -qE "$filter"; then
        log_debug "Tag '$tag' matches regex '$filter'"
        return 0
    else
        log_debug "Tag '$tag' does not match regex '$filter'"
        return 1
    fi
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OCI Registry Cleanup Script - Removes artifacts older than specified retention period

Required Environment Variables:
  REGISTRY_URL          OCI registry URL (e.g., registry.example.com or ghcr.io)
  REGISTRY_USERNAME     Username for registry authentication
  REGISTRY_PASSWORD     Password or token for registry authentication

Optional Environment Variables:
  ARTIFACT_FILTER       Comma-separated prefixes (e.g., "backend-api,worker-service") or regex
                        If empty, all artifacts are processed (default: empty)
  TAG_FILTER           Regex pattern to match image tags (e.g., "^master-.*" or ".*-snapshot$")
                        If empty, all tags are processed (default: empty)
  RETENTION_DAYS        Delete artifacts older than this many days (default: 30)
  DRY_RUN              Set to 'true' to preview deletions without executing (default: false)
  BATCH_SIZE           Number of artifacts to process in parallel (default: 10)
  LOG_LEVEL            Logging verbosity: DEBUG, INFO, WARN, ERROR (default: INFO)

Examples:
  # Delete all artifacts older than 60 days (dry run)
  REGISTRY_URL="registry.example.com" \\
  REGISTRY_USERNAME="user" \\
  REGISTRY_PASSWORD="pass" \\
  RETENTION_DAYS=60 \\
  DRY_RUN=true \\
  $0

  # Delete only specific services older than 7 days
  REGISTRY_URL="ghcr.io/myorg" \\
  REGISTRY_USERNAME="token" \\
  REGISTRY_PASSWORD="ghp_xxx" \\
  ARTIFACT_FILTER="auth-service,payment-api,notification-worker" \\
  RETENTION_DAYS=7 \\
  $0

  # Delete only master branch tags from specific service
  ARTIFACT_FILTER="inventory-service" \\
  TAG_FILTER="^master-.*" \\
  RETENTION_DAYS=30 \\
  $0

  # Delete only snapshot tags older than 7 days
  TAG_FILTER=".*-snapshot$" \\
  RETENTION_DAYS=7 \\
  $0

EOF
    exit 1
}

# Function to check required dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in curl jq date; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install: apt-get install curl jq coreutils (or equivalent)"
        exit 1
    fi
}

# Function to validate configuration
validate_config() {
    local errors=()
    
    [[ -z "$REGISTRY_URL" ]] && errors+=("REGISTRY_URL is required")
    [[ -z "$REGISTRY_USERNAME" ]] && errors+=("REGISTRY_USERNAME is required")
    [[ -z "$REGISTRY_PASSWORD" ]] && errors+=("REGISTRY_PASSWORD is required")
    
    if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [[ "$RETENTION_DAYS" -lt 0 ]]; then
        errors+=("RETENTION_DAYS must be a positive integer")
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Configuration validation failed:"
        printf '%s\n' "${errors[@]}" >&2
        echo ""
        usage
    fi
    
    log_info "Configuration validated successfully"
}

# Function to calculate cutoff timestamp
calculate_cutoff_date() {
    local days=$1
    
    # Get current timestamp and subtract retention days
    if date --version &>/dev/null 2>&1; then
        # GNU date (Linux)
        date -d "$days days ago" -u +"%Y-%m-%dT%H:%M:%SZ"
    else
        # BSD date (macOS)
        date -u -v-"${days}d" +"%Y-%m-%dT%H:%M:%SZ"
    fi
}

# Function to make authenticated API calls
api_call() {
    local method=$1
    local url=$2
    local auth_header="Authorization: Basic $(echo -n "${REGISTRY_USERNAME}:${REGISTRY_PASSWORD}" | base64)"
    
    local response
    local http_code
    
    # Use -L to follow redirects (important for Azure Container Registry and other registries that use blob storage redirects)
    response=$(curl -s -L -w "\n%{http_code}" -X "$method" \
        -H "$auth_header" \
        -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json" \
        "$url")
    
    http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    log_debug "API Call: $method $url -> HTTP $http_code"
    
    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        echo "$body"
        return 0
    else
        log_error "API call failed: $method $url (HTTP $http_code)"
        log_debug "Response: $body"
        return 1
    fi
}

# Function to list repositories
list_repositories() {
    local registry=$1
    local catalog_url="https://${registry}/v2/_catalog"
    
    log_info "Fetching repository catalog from $registry"
    
    local response
    if ! response=$(api_call "GET" "$catalog_url"); then
        log_error "Failed to fetch repository catalog"
        return 1
    fi
    
    echo "$response" | jq -r '.repositories[]? // empty'
}

# Function to list tags for a repository
list_tags() {
    local registry=$1
    local repo=$2
    local tags_url="https://${registry}/v2/${repo}/tags/list"
    
    log_debug "Fetching tags for repository: $repo"
    
    local response
    if ! response=$(api_call "GET" "$tags_url"); then
        log_warn "Failed to fetch tags for repository: $repo"
        return 1
    fi
    
    echo "$response" | jq -r '.tags[]? // empty'
}

# Function to get manifest digest
get_manifest_digest() {
    local registry=$1
    local repo=$2
    local tag=$3
    local manifest_url="https://${registry}/v2/${repo}/manifests/${tag}"
    
    local auth_header="Authorization: Basic $(echo -n "${REGISTRY_USERNAME}:${REGISTRY_PASSWORD}" | base64)"
    
    local digest
    digest=$(curl -s -I -X GET \
        -H "$auth_header" \
        -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json" \
        "$manifest_url" | grep -i "docker-content-digest:" | awk '{print $2}' | tr -d '\r')
    
    echo "$digest"
}

# Function to get image creation date
get_image_created_date() {
    local registry=$1
    local repo=$2
    local tag=$3
    local manifest_url="https://${registry}/v2/${repo}/manifests/${tag}"
    
    log_debug "Getting creation date for ${repo}:${tag}"
    
    local manifest
    if ! manifest=$(api_call "GET" "$manifest_url"); then
        log_warn "Failed to fetch manifest for ${repo}:${tag}"
        return 1
    fi
    
    log_debug "Manifest retrieved, analyzing structure..."
    
    # Try to get creation date from manifest
    local created_date
    local media_type
    media_type=$(echo "$manifest" | jq -r '.mediaType // empty')
    
    log_debug "Manifest media type: ${media_type:-unknown}"
    
    # Handle manifest lists (multi-arch images)
    if [[ "$media_type" =~ "manifest.list" ]] || [[ "$media_type" =~ "image.index" ]]; then
        log_debug "Detected manifest list/index, getting first manifest"
        local first_digest
        first_digest=$(echo "$manifest" | jq -r '.manifests[0].digest // empty')
        
        if [[ -n "$first_digest" ]]; then
            local sub_manifest_url="https://${registry}/v2/${repo}/manifests/${first_digest}"
            log_debug "Fetching sub-manifest: ${first_digest}"
            if manifest=$(api_call "GET" "$sub_manifest_url"); then
                media_type=$(echo "$manifest" | jq -r '.mediaType // empty')
                log_debug "Sub-manifest media type: ${media_type:-unknown}"
            fi
        fi
    fi
    
    # Method 1: Check if it's an OCI/Docker manifest with config blob
    local config_digest
    config_digest=$(echo "$manifest" | jq -r '.config.digest // empty')
    
    if [[ -n "$config_digest" ]]; then
        log_debug "Found config digest: ${config_digest}"
        local blob_url="https://${registry}/v2/${repo}/blobs/${config_digest}"
        local config
        if config=$(api_call "GET" "$blob_url"); then
            created_date=$(echo "$config" | jq -r '.created // .Created // empty')
            if [[ -n "$created_date" ]]; then
                log_debug "Got creation date from config blob: ${created_date}"
            fi
        else
            log_debug "Failed to fetch config blob"
        fi
    else
        log_debug "No config digest found in manifest"
    fi
    
    # Method 2: Try to get from v1Compatibility in manifest history
    if [[ -z "$created_date" ]]; then
        log_debug "Trying to extract date from manifest history..."
        local v1_compat
        v1_compat=$(echo "$manifest" | jq -r '.history[0].v1Compatibility // empty')
        if [[ -n "$v1_compat" ]]; then
            created_date=$(echo "$v1_compat" | jq -r '.created // empty')
            if [[ -n "$created_date" ]]; then
                log_debug "Got creation date from history: ${created_date}"
            fi
        fi
    fi
    
    # Method 3: Try schemaVersion 1 format (older Docker registries)
    if [[ -z "$created_date" ]]; then
        log_debug "Trying schema v1 format..."
        created_date=$(echo "$manifest" | jq -r '.history[0]? // empty' | jq -r 'fromjson? | .created // empty' 2>/dev/null || echo "")
        if [[ -n "$created_date" ]]; then
            log_debug "Got creation date from schema v1: ${created_date}"
        fi
    fi
    
    # Method 4: Try annotations (some registries add this)
    if [[ -z "$created_date" ]]; then
        log_debug "Trying annotations..."
        created_date=$(echo "$manifest" | jq -r '.annotations."org.opencontainers.image.created" // .annotations.created // empty')
        if [[ -n "$created_date" ]]; then
            log_debug "Got creation date from annotations: ${created_date}"
        fi
    fi
    
    # Last resort: return empty to signal we couldn't determine date
    if [[ -z "$created_date" ]]; then
        log_warn "Could not determine creation date for ${repo}:${tag} after trying all methods"
        log_debug "Manifest structure: $(echo "$manifest" | jq -c '.' | head -c 200)"
        return 1
    fi
    
    echo "$created_date"
}

# Function to delete manifest
delete_manifest() {
    local registry=$1
    local repo=$2
    local digest=$3
    local delete_url="https://${registry}/v2/${repo}/manifests/${digest}"
    
    log_info "Deleting ${repo}@${digest}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete: ${repo}@${digest}"
        return 0
    fi
    
    if api_call "DELETE" "$delete_url" > /dev/null 2>&1; then
        log_info "Successfully deleted ${repo}@${digest}"
        return 0
    else
        log_error "Failed to delete ${repo}@${digest}"
        return 1
    fi
}

# Function to compare dates
is_older_than_cutoff() {
    local image_date=$1
    local cutoff_date=$2
    
    # Convert dates to timestamps for comparison
    local image_ts
    local cutoff_ts
    
    if date --version &>/dev/null 2>&1; then
        # GNU date
        image_ts=$(date -d "$image_date" +%s 2>/dev/null || echo 0)
        cutoff_ts=$(date -d "$cutoff_date" +%s 2>/dev/null || echo 0)
    else
        # BSD date
        image_ts=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${image_date%Z}" +%s 2>/dev/null || echo 0)
        cutoff_ts=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${cutoff_date%Z}" +%s 2>/dev/null || echo 0)
    fi
    
    [[ $image_ts -lt $cutoff_ts ]]
}

# Main cleanup function
cleanup_registry() {
    local registry=$1
    local cutoff_date
    cutoff_date=$(calculate_cutoff_date "$RETENTION_DAYS")
    
    log_info "Starting OCI registry cleanup"
    log_info "Registry: $registry"
    log_info "Artifact filter: ${ARTIFACT_FILTER:-all}"
    log_info "Tag filter: ${TAG_FILTER:-all}"
    log_info "Retention period: $RETENTION_DAYS days"
    log_info "Cutoff date: $cutoff_date"
    log_info "Dry run: $DRY_RUN"
    echo ""
    
    local total_repos=0
    local total_artifacts=0
    local total_deleted=0
    local total_skipped=0
    local total_errors=0
    
    # List all repositories
    local repositories
    if ! repositories=$(list_repositories "$registry"); then
        log_error "Failed to list repositories"
        return 1
    fi
    
    if [[ -z "$repositories" ]]; then
        log_info "No repositories found in registry"
        return 0
    fi
    
    while IFS= read -r repo; do
        [[ -z "$repo" ]] && continue
        
        # Apply artifact filter
        if ! matches_filter "$repo"; then
            log_debug "Skipping repository $repo (does not match filter)"
            continue
        fi
        
        ((total_repos++))
        log_info "Processing repository: $repo"
        
        # List tags for repository
        local tags
        if ! tags=$(list_tags "$registry" "$repo"); then
            log_warn "Skipping repository $repo (could not list tags)"
            continue
        fi
        
        if [[ -z "$tags" ]]; then
            log_debug "No tags found in repository: $repo"
            continue
        fi
        
        while IFS= read -r tag; do
            [[ -z "$tag" ]] && continue
            ((total_artifacts++))
            
            # Apply tag filter
            if ! matches_tag_filter "$tag"; then
                log_debug "Skipping tag ${repo}:${tag} (does not match tag filter)"
                continue
            fi
            
            # Get image creation date
            local created_date
            if ! created_date=$(get_image_created_date "$registry" "$repo" "$tag"); then
                log_warn "Could not get creation date for ${repo}:${tag}, skipping"
                ((total_skipped++))
                continue
            fi
            
            log_debug "Image ${repo}:${tag} created at: $created_date"
            
            # Check if image is older than cutoff
            if is_older_than_cutoff "$created_date" "$cutoff_date"; then
                log_info "Image ${repo}:${tag} is older than $RETENTION_DAYS days"
                
                # Get manifest digest
                local digest
                digest=$(get_manifest_digest "$registry" "$repo" "$tag")
                
                if [[ -z "$digest" ]]; then
                    log_error "Could not get digest for ${repo}:${tag}"
                    ((total_errors++))
                    continue
                fi
                
                # Delete the manifest
                if delete_manifest "$registry" "$repo" "$digest"; then
                    ((total_deleted++))
                else
                    ((total_errors++))
                fi
            else
                log_debug "Image ${repo}:${tag} is within retention period, keeping"
            fi
        done <<< "$tags"
        
    done <<< "$repositories"
    
    echo ""
    log_info "==================== Cleanup Summary ===================="
    log_info "Repositories processed: $total_repos"
    log_info "Total artifacts scanned: $total_artifacts"
    log_info "Artifacts deleted: $total_deleted"
    log_info "Artifacts skipped (no date): $total_skipped"
    log_info "Errors encountered: $total_errors"
    log_info "========================================================"
    
    return 0
}

# Main script execution
main() {
    log_info "OCI Registry Cleanup Script Started"
    
    # Check for help flag
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
    fi
    
    # Check dependencies
    check_dependencies
    
    # Validate configuration
    validate_config
    
    # Strip protocol from registry URL if present
    REGISTRY_URL="${REGISTRY_URL#https://}"
    REGISTRY_URL="${REGISTRY_URL#http://}"
    
    # Run cleanup
    if cleanup_registry "$REGISTRY_URL"; then
        log_info "Cleanup completed successfully"
        exit 0
    else
        log_error "Cleanup completed with errors"
        exit 1
    fi
}

# Execute main function
main "$@"
