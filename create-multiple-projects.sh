#!/bin/bash

# Check if at least 2 arguments are provided (branch + at least one git URL)
if [ $# -lt 2 ]; then
    echo "Usage: $0 <branch> <git-url1> [git-url2] [git-url3] ..."
    echo "Example: $0 develop https://bitbucket.com/scm/george/raj_ab1234_cd23456.git https://bitbucket.com/scm/george/alice_xy9876_zw5432.git"
    exit 1
fi

# Get the script directory (root of the project)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Assign branch from first argument
branch="$1"
shift  # Remove the first argument (branch) from the argument list

# Path to the create-project-helms.sh script
CREATE_SCRIPT="$SCRIPT_DIR/create-project-helms.sh"

# Check if create-project-helms.sh exists
if [ ! -f "$CREATE_SCRIPT" ]; then
    echo "Error: create-project-helms.sh not found at: $CREATE_SCRIPT"
    exit 1
fi

# Make sure create-project-helms.sh is executable
chmod +x "$CREATE_SCRIPT"

echo "Creating projects for branch: $branch"
echo "Processing ${#@} git repositories..."
echo ""

# Counter for tracking progress
counter=1
total=$#
failed_repos=()

# Iterate over all remaining arguments (git URLs)
for gitUrl in "$@"; do
    echo "=========================================="
    echo "Processing repository $counter of $total"
    echo "Git URL: $gitUrl"
    echo "Branch: $branch"
    echo "=========================================="
    
    # Call create-project-helms.sh with the current git URL and branch
    if "$CREATE_SCRIPT" "$gitUrl" "$branch"; then
        echo "✅ Successfully created project for: $gitUrl"
    else
        echo "❌ Failed to create project for: $gitUrl"
        failed_repos+=("$gitUrl")
    fi
    
    echo ""
    ((counter++))
done

# Summary
echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo "Total repositories processed: $total"
echo "Successful: $((total - ${#failed_repos[@]}))"
echo "Failed: ${#failed_repos[@]}"

if [ ${#failed_repos[@]} -gt 0 ]; then
    echo ""
    echo "Failed repositories:"
    for repo in "${failed_repos[@]}"; do
        echo "  - $repo"
    done
    exit 1
else
    echo ""
    echo "🎉 All repositories processed successfully!"
    exit 0
fi
