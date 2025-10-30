#!/bin/bash

set -e

NAMESPACE="gitlab"
DOMAIN="k3d.gitlab.com"
GITLAB_HOST="gitlab.${DOMAIN}"

# Get GitLab URL
GITLAB_URL="http://${GITLAB_HOST}:8181"

# Get credentials from k8s secret
USERNAME="root"
PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n "$NAMESPACE" -o jsonpath="{.data.password}" | base64 -d)

read -p "Repo Name: " REPO_NAME
read -p "Folder Path: " FOLDER_PATH

echo "Creating repo '$REPO_NAME' on $GITLAB_URL..."

# Create repo
RESPONSE=$(curl -s -X POST "$GITLAB_URL/api/v4/projects" \
    --user "$USERNAME:$PASSWORD" \
    -F "name=$REPO_NAME" \
    -F "visibility=private")

# Debug: check if repo was created
if echo "$RESPONSE" | grep -q "error"; then
    echo "Error creating repository:"
    echo "$RESPONSE"
    exit 1
fi

# Extract HTTP URL (try multiple methods)
HTTP_URL=$(echo "$RESPONSE" | grep -o '"http_url_to_repo":"[^"]*' | cut -d'"' -f4)
if [ -z "$HTTP_URL" ]; then
    # Fallback: construct URL manually
    PROJECT_ID=$(echo "$RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    HTTP_URL="http://$GITLAB_HOST:8181/$USERNAME/$REPO_NAME.git"
fi

echo "Repository URL: $HTTP_URL"

# Push folder
cd "$FOLDER_PATH"
git init
git checkout -b main

# Create manifests directory and move files there
mkdir -p manifests
# Move all files except .git to manifests
find . -maxdepth 1 -type f -exec mv {} manifests/ \;
# Move subdirectories if any (except .git)
find . -maxdepth 1 -mindepth 1 -type d ! -name '.git' ! -name 'manifests' -exec mv {} manifests/ \;

git add .
git commit -m "Initial commit"
git remote add origin "$HTTP_URL"

# Configure git to use the credentials
git config credential.helper store
echo "http://$USERNAME:$PASSWORD@$GITLAB_HOST:8181" > ~/.git-credentials

git push -u origin main

echo ""
echo "✓ Done!"
echo "  Repository: $HTTP_URL"
