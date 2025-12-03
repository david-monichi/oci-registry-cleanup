# OCI Registry Cleanup Script

A versatile bash script for cleaning up old OCI (Open Container Initiative) artifacts from container registries. Supports running as a standalone script, CI/CD pipeline job, or Kubernetes CronJob.

## Features

- ✅ Deletes OCI artifacts older than a configurable retention period
- ✅ Supports prefix list or regex pattern filtering for artifact names
- ✅ Supports regex pattern filtering for image tags
- ✅ Dry-run mode to preview deletions
- ✅ Compatible with OCI-compliant registries (Docker Hub, GHCR, Harbor, ACR, GCR, etc.)
- ✅ Configurable via environment variables
- ✅ Detailed logging with multiple log levels
- ✅ Can run as standalone script, CI/CD pipeline, or Kubernetes CronJob
- ✅ Handles authentication securely

## Prerequisites

- `bash` (version 4.0+)
- `curl`
- `jq`
- `coreutils` (for date manipulation)

## Quick Start

### Standalone Usage

```bash
# Make the script executable
chmod +x cleanup-oci-artifacts.sh

# Run with environment variables
REGISTRY_URL="registry.example.com" \
REGISTRY_USERNAME="myuser" \
REGISTRY_PASSWORD="mypassword" \
RETENTION_DAYS=30 \
DRY_RUN=true \
./cleanup-oci-artifacts.sh
```

### Docker Usage

```bash
# Build the Docker image
docker build -t oci-registry-cleanup:latest .

# Run as container
docker run --rm \
  -e REGISTRY_URL="registry.example.com" \
  -e REGISTRY_USERNAME="myuser" \
  -e REGISTRY_PASSWORD="mypassword" \
  -e RETENTION_DAYS=30 \
  -e DRY_RUN=true \
  oci-registry-cleanup:latest
```

## Configuration

All configuration is done via environment variables:

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `REGISTRY_URL` | OCI registry URL (without protocol) | `registry.example.com` or `ghcr.io` |
| `REGISTRY_USERNAME` | Username for registry authentication | `myuser` or `token` |
| `REGISTRY_PASSWORD` | Password or token for authentication | `mypassword` or `ghp_xxxxx` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ARTIFACT_FILTER` | (empty) | Comma-separated list of prefixes (e.g., `"web-app,api-service,worker"`) or regex pattern. If empty, all artifacts are processed |
| `TAG_FILTER` | (empty) | Regex pattern to match image tags (e.g., `"^master-.*"` or `".*-snapshot$"`). If empty, all tags are processed |
| `RETENTION_DAYS` | `30` | Delete artifacts older than this many days |
| `DRY_RUN` | `false` | Set to `true` to preview deletions without executing |
| `BATCH_SIZE` | `10` | Number of artifacts to process in parallel |
| `LOG_LEVEL` | `INFO` | Logging verbosity: `DEBUG`, `INFO`, `WARN`, `ERROR` |

## Usage Examples

### Example 1: Delete specific services using prefix list

```bash
REGISTRY_URL="ghcr.io/myorg" \
REGISTRY_USERNAME="token" \
REGISTRY_PASSWORD="ghp_xxxxxxxxxxxxx" \
ARTIFACT_FILTER="backend-api,frontend-app,worker-service" \
RETENTION_DAYS=7 \
./cleanup-oci-artifacts.sh
```

### Example 2: Dry run to see what would be deleted

```bash
REGISTRY_URL="registry.example.com" \
REGISTRY_USERNAME="myuser" \
REGISTRY_PASSWORD="mypass" \
RETENTION_DAYS=60 \
DRY_RUN=true \
LOG_LEVEL=DEBUG \
./cleanup-oci-artifacts.sh
```

### Example 3: Clean up specific project artifacts

```bash
REGISTRY_URL="harbor.company.com" \
REGISTRY_USERNAME="admin" \
REGISTRY_PASSWORD="Harbor12345" \
ARTIFACT_FILTER="myproject" \
RETENTION_DAYS=90 \
./cleanup-oci-artifacts.sh
```

### Example 4: Delete only master branch tags from specific service

```bash
REGISTRY_URL="registry.example.com" \
REGISTRY_USERNAME="myuser" \
REGISTRY_PASSWORD="xxxxx" \
ARTIFACT_FILTER="payment-service" \
TAG_FILTER="^master-.*" \
RETENTION_DAYS=60 \
./cleanup-oci-artifacts.sh
```

### Example 5: Delete only snapshot tags across all services

```bash
REGISTRY_URL="registry.example.com" \
REGISTRY_USERNAME="myuser" \
REGISTRY_PASSWORD="mypass" \
TAG_FILTER=".*-snapshot$" \
RETENTION_DAYS=7 \
DRY_RUN=false \
./cleanup-oci-artifacts.sh
```

### Example 6: Delete development tags using regex

```bash
REGISTRY_URL="ghcr.io/myorg" \
REGISTRY_USERNAME="token" \
REGISTRY_PASSWORD="ghp_xxxxx" \
TAG_FILTER="^(dev|feature|test)-.*" \
RETENTION_DAYS=14 \
./cleanup-oci-artifacts.sh
```

### Example 7: Combine artifact and tag filters

```bash
REGISTRY_URL="harbor.company.com" \
REGISTRY_USERNAME="admin" \
REGISTRY_PASSWORD="Harbor12345" \
ARTIFACT_FILTER="inventory-service,notification-worker" \
TAG_FILTER="^(staging|qa)-[0-9]+" \
RETENTION_DAYS=30 \
./cleanup-oci-artifacts.sh
```

## Filter Patterns

### Artifact Filter

The `ARTIFACT_FILTER` supports two modes:

**1. Prefix List Mode** (contains comma)
```bash
ARTIFACT_FILTER="auth-service,data-processor,notification-api"
```
- Matches any repository that starts with the specified prefixes
- `auth-service` matches: `auth-service`, `auth-service-api`, `auth-service/v1`
- Multiple prefixes are comma-separated
- Whitespace around commas is automatically trimmed

**2. Regex Mode** (no comma)
```bash
ARTIFACT_FILTER=".*backend.*"     # Matches any repo containing 'backend'
ARTIFACT_FILTER="^myproject/.*"   # Matches repos starting with 'myproject/'
ARTIFACT_FILTER=".*(dev|test).*"  # Matches repos containing 'dev' or 'test'
```
- Uses standard extended regex (grep -E)
- Matches anywhere in the repository name

**3. Match All** (empty)
```bash
ARTIFACT_FILTER=""  # Processes all repositories
```

### Tag Filter

The `TAG_FILTER` uses regex patterns to match image tags:

```bash
# Match tags starting with 'master-'
TAG_FILTER="^master-.*"

# Match snapshot tags
TAG_FILTER=".*-snapshot$"

# Match development tags
TAG_FILTER="^(dev|develop|feature)-.*"

# Match semantic version tags
TAG_FILTER="^v[0-9]+\.[0-9]+\.[0-9]+$"

# Match build number tags
TAG_FILTER="^[0-9]+-[a-f0-9]+$"

# Match PR tags
TAG_FILTER="^pr-[0-9]+"

# Multiple patterns (OR)
TAG_FILTER="^(staging|qa|test)-.*"
```

**Regex Syntax:**
- `^` - Start of string
- `$` - End of string
- `.*` - Any characters
- `|` - OR condition
- `[0-9]+` - One or more digits
- `[a-f0-9]+` - Hex characters
- `\` - Escape special characters

**Common Patterns:**

| Pattern | Description | Example Matches |
|---------|-------------|----------------|
| `^master-.*` | Master branch builds | `master-123-abc456` |
| `^v[0-9].*` | Version tags | `v1.2.3`, `v2.0.0-rc1` |
| `.*-snapshot$` | Snapshot releases | `1.0.0-snapshot`, `latest-snapshot` |
| `^(dev\|test).*` | Dev/test tags | `dev-feature`, `test-123` |
| `^pr-[0-9]+` | Pull request builds | `pr-42`, `pr-123` |
| `[0-9]{8}` | Date-based tags | `20231215` |

## Kubernetes Deployment

### Option 1: Using ConfigMap for script

```bash
# Create the ConfigMap from the script file
kubectl create configmap oci-cleanup-script \
  --from-file=cleanup-oci-artifacts.sh=./cleanup-oci-artifacts.sh

# Create secrets for credentials
kubectl create secret generic oci-registry-credentials \
  --from-literal=username='myuser' \
  --from-literal=password='mypassword'

# Create the ConfigMap for configuration
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: oci-cleanup-config
data:
  REGISTRY_URL: "registry.example.com"
  ARTIFACT_FILTER: "billing-service,analytics-worker"
  TAG_FILTER: ""
  RETENTION_DAYS: "30"
  DRY_RUN: "false"
  LOG_LEVEL: "INFO"
EOF

# Deploy the CronJob
kubectl apply -f kubernetes-cronjob.yaml
```

### Option 2: Using Docker image

```bash
# Build and push the Docker image
docker build -t myregistry.com/oci-cleanup:latest .
docker push myregistry.com/oci-cleanup:latest

# Update kubernetes-cronjob.yaml to use your image
# Then apply:
kubectl apply -f kubernetes-cronjob.yaml
```

### View CronJob status

```bash
# List CronJobs
kubectl get cronjobs

# View jobs created by CronJob
kubectl get jobs

# View logs from latest job
kubectl logs -l app=oci-registry-cleanup --tail=100
```

## CI/CD Pipeline Integration

### GitHub Actions

1. Copy `.github-actions-example.yaml` to `.github/workflows/oci-cleanup.yaml`
2. Set up repository secrets:
   - `REGISTRY_URL`
   - `REGISTRY_USERNAME`
   - `REGISTRY_PASSWORD`
3. Customize schedule and parameters as needed

### GitLab CI

1. Copy `.gitlab-ci-example.yml` to `.gitlab-ci.yml`
2. Set up CI/CD variables in GitLab:
   - `REGISTRY_URL`
   - `REGISTRY_USERNAME`
   - `REGISTRY_PASSWORD` (masked)
   - `RETENTION_DAYS`
   - `DRY_RUN`
3. Configure pipeline schedule in GitLab UI

### Jenkins

```groovy
pipeline {
    agent any
    
    triggers {
        cron('0 2 * * *') // Daily at 2 AM
    }
    
    environment {
        REGISTRY_URL = 'registry.example.com'
        REGISTRY_USERNAME = credentials('registry-username')
        REGISTRY_PASSWORD = credentials('registry-password')
        RETENTION_DAYS = '30'
        DRY_RUN = 'false'
    }
    
    stages {
        stage('Cleanup') {
            steps {
                sh '''
                    chmod +x cleanup-oci-artifacts.sh
                    ./cleanup-oci-artifacts.sh
                '''
            }
        }
    }
}
```

## Supported Registries

This script works with any OCI-compliant registry that supports the [Docker Registry HTTP API V2](https://docs.docker.com/registry/spec/api/), including:

- ✅ Docker Hub
- ✅ GitHub Container Registry (GHCR)
- ✅ GitLab Container Registry
- ✅ Harbor
- ✅ Azure Container Registry (ACR)
- ✅ Google Container Registry (GCR)
- ✅ Amazon ECR (with proper authentication)
- ✅ Quay.io
- ✅ JFrog Artifactory

## Registry-Specific Notes

### GitHub Container Registry (GHCR)

```bash
REGISTRY_URL="ghcr.io/myorg"
REGISTRY_USERNAME="myusername"
REGISTRY_PASSWORD="ghp_xxxxxxxxxxxxx"  # Personal Access Token with delete:packages scope
```

### Docker Hub

```bash
REGISTRY_URL="registry.hub.docker.com/myusername"
REGISTRY_USERNAME="myusername"
REGISTRY_PASSWORD="mypassword"  # or Docker Access Token
```

### Harbor

```bash
REGISTRY_URL="harbor.example.com"
REGISTRY_USERNAME="admin"
REGISTRY_PASSWORD="Harbor12345"
```

### Azure Container Registry (ACR)

```bash
REGISTRY_URL="myregistry.azurecr.io"
REGISTRY_USERNAME="myregistry"
REGISTRY_PASSWORD="xxxxx"  # ACR admin password or service principal
```

## Troubleshooting

### Enable debug logging

```bash
LOG_LEVEL=DEBUG ./cleanup-oci-artifacts.sh
```

### Common issues

**Issue**: "401 Unauthorized" errors
- **Solution**: Verify credentials are correct and have delete permissions

**Issue**: "Could not determine creation date"
- **Solution**: Some registries don't expose creation timestamps. These artifacts will be skipped.

**Issue**: Script runs but nothing is deleted
- **Solution**: Check if `DRY_RUN=true`. Verify artifacts match the filter and are older than retention period.

**Issue**: "Missing required dependencies"
- **Solution**: Install curl, jq, and coreutils: `apt-get install curl jq coreutils`

## Security Considerations

- ⚠️ Store credentials securely (use secrets management)
- ⚠️ Use tokens with minimum required permissions
- ⚠️ Always test with `DRY_RUN=true` first
- ⚠️ Implement proper RBAC in Kubernetes
- ⚠️ Use read-only filesystem in containers where possible
- ⚠️ Run containers as non-root user (included in Dockerfile)

## Performance

- Script processes artifacts sequentially by default
- For large registries, consider running multiple instances with different filters
- Adjust `BATCH_SIZE` for parallel processing (future enhancement)
- Consider running during off-peak hours

## License

MIT License - feel free to use and modify as needed.

## Contributing

Contributions welcome! Please test thoroughly before submitting pull requests.

## Support

For issues or questions, please open a GitHub issue.
