#!/bin/bash

# Check if git URL and branch arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <git-clone-url> <branch>"
    echo "Example: $0 https://bitbucket.com/scm/george/raj_ab1234_cd23456.git develop"
    exit 1
fi

# Assign arguments to variables
gitUrl="$1"
branch="$2"

# Get the script directory (root of the project)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Extract organization and repository name from Bitbucket URL
if [[ "$gitUrl" =~ https://bitbucket\.com/scm/([^/]+)/([^/]+)\.git$ ]]; then
    # Bitbucket format: https://bitbucket.com/scm/organization/repository.git
    organization="${BASH_REMATCH[1]}"
    repository="${BASH_REMATCH[2]}"
else
    echo "Error: Invalid Bitbucket URL format: $gitUrl"
    echo "Expected format: https://bitbucket.com/scm/organization/repository.git"
    exit 1
fi

# Extract parentAssetId and assetId from repository name
# Look for the last two underscore-separated parts (e.g., raj_ab1234_ab1234_cd23456 -> ab1234, cd23456)
if [[ "$repository" =~ _([^_]+)_([^_]+)$ ]]; then
    parentAssetId="${BASH_REMATCH[1]}"
    assetId="${BASH_REMATCH[2]}"
else
    echo "Warning: Repository name '$repository' does not contain at least two underscore-separated parts at the end"
    echo "parentAssetId and assetId will not be available"
    parentAssetId=""
    assetId=""
fi

# Set imageName to repository name (for now)
imageName="$repository"

echo "Extracted organization: $organization"
echo "Extracted repository: $repository"
echo "Image name: $imageName"
echo "Branch: $branch"
if [ -n "$parentAssetId" ] && [ -n "$assetId" ]; then
    echo "Extracted parentAssetId: $parentAssetId"
    echo "Extracted assetId: $assetId"
fi

# Create organization directory
orgPath="$SCRIPT_DIR/$organization"
if [ ! -d "$orgPath" ]; then
    mkdir -p "$orgPath"
    echo "Created organization directory: $orgPath"
else
    echo "Using existing organization directory: $orgPath"
fi

# Create repository directory
repoPath="$orgPath/$repository"
if [ -d "$repoPath" ]; then
    echo "Warning: Repository directory already exists: $repoPath"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting..."
        exit 1
    fi
    rm -rf "$repoPath"
fi

mkdir -p "$repoPath"
echo "Created repository directory: $repoPath"

# Copy sample contents to the new repository directory
samplePath="$SCRIPT_DIR/sample"
if [ ! -d "$samplePath" ]; then
    echo "Error: Sample directory not found at: $samplePath"
    exit 1
fi

# Copy all contents from sample to the new repository directory
cp -r "$samplePath"/* "$repoPath/"
echo "Copied sample contents to: $repoPath"

# Replace placeholder values in all files if parentAssetId and assetId are available
if [ -n "$parentAssetId" ] && [ -n "$assetId" ]; then
    echo "Replacing placeholder values in files..."
    
    # Find all files (excluding binary files) and replace placeholders
    find "$repoPath" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.xml" -o -name "*.tpl" -o -name "*.txt" -o -name "*.md" \) -exec sed -i "s/<parentAssetId>/$parentAssetId/g; s/<assetId>/$assetId/g; s/<organization>/$organization/g; s/<repository>/$repository/g; s/<imageName>/$imageName/g; s/<branch>/$branch/g" {} \;
    
    echo "Replaced placeholders:"
    echo "  <parentAssetId> -> $parentAssetId"
    echo "  <assetId> -> $assetId"
    echo "  <organization> -> $organization"
    echo "  <repository> -> $repository"
    echo "  <imageName> -> $imageName"
    echo "  <branch> -> $branch"
else
    echo "Skipping placeholder replacement (parentAssetId or assetId not available)"
fi

echo ""
echo "Project structure created successfully!"
echo "Organization: $organization"
echo "Repository: $repository"
echo "Project path: $repoPath"
echo ""
echo "Contents copied from sample:"
ls -la "$repoPath"

# Chain with create-pdm.sh if parentAssetId and assetId are available
if [ -n "$parentAssetId" ] && [ -n "$assetId" ]; then
    echo ""
    echo "=========================================="
    echo "Creating PDM structure..."
    echo "=========================================="
    
    # Path to the create-pdm.sh script (in spring-boot-app folder)
    PDM_SCRIPT="$SCRIPT_DIR/spring-boot-app/create-pdm.sh"
    
    # Check if create-pdm.sh exists
    if [ -f "$PDM_SCRIPT" ]; then
        # Make sure create-pdm.sh is executable
        chmod +x "$PDM_SCRIPT"
        
        # Navigate to the repository directory
        cd "$repoPath"
        
        # Call create-pdm.sh with mapped parameters
        # productName=product, imageName=imageName, testEngine=cucumber, fabId=assetId
        if "$PDM_SCRIPT" "product" "$imageName" "cucumber" "$assetId"; then
            echo "✅ PDM structure created successfully"
            
            # Create zip file
            if [ -d "pdm" ]; then
                zipFileName="${repository}-pdm.zip"
                echo "Creating zip file: $zipFileName"
                
                if zip -r "$zipFileName" pdm/; then
                    echo "✅ Created zip file: $zipFileName"
                    
                    # Delete the pdm folder
                    echo "Cleaning up pdm folder..."
                    rm -rf pdm/
                    echo "✅ PDM folder deleted"
                else
                    echo "❌ Failed to create zip file"
                fi
            else
                echo "❌ PDM folder not found, skipping zip creation"
            fi
        else
            echo "❌ Failed to create PDM structure"
        fi
        
        # Return to original directory
        cd "$SCRIPT_DIR"
    else
        echo "⚠️  create-pdm.sh not found at: $PDM_SCRIPT"
        echo "Skipping PDM creation"
    fi
else
    echo ""
    echo "⚠️  Skipping PDM creation (parentAssetId or assetId not available)"
fi
