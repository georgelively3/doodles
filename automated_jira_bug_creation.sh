#!/bin/bash

# Interactive Jira Bug Creation from Confluence Table
# This script reads a table from a Confluence page and creates Jira bugs

echo "=========================================="
echo "Automated Jira Bug Creation from Confluence"
echo "=========================================="

# Function to validate URL format
validate_url() {
    local url="$1"
    if [[ "$url" =~ ^https?:// ]]; then
        return 0
    else
        return 1
    fi
}

# Function to prompt for user input
prompt_input() {
    local prompt="$1"
    local variable_name="$2"
    local is_required="$3"
    
    while true; do
        read -p "$prompt: " input
        if [ -n "$input" ] || [ "$is_required" != "required" ]; then
            eval "$variable_name=\"$input\""
            break
        else
            echo "This field is required. Please enter a value."
        fi
    done
}

# Function to get SSO session info
get_sso_auth() {
    echo ""
    echo "=========================================="
    echo "SSO Authentication Setup"
    echo "=========================================="
    echo "Since your organization uses SSO, you'll need to provide session authentication."
    echo "Please choose one of the following options:"
    echo ""
    echo "1. Provide session cookies (recommended)"
    echo "2. Provide authorization header"
    echo "3. Use browser session (requires manual cookie export)"
    echo ""
    
    read -p "Choose option (1-3): " auth_option
    
    case $auth_option in
        1)
            echo "Please export your session cookies from your browser:"
            echo "1. Log into Confluence/Jira in your browser"
            echo "2. Open Developer Tools (F12)"
            echo "3. Go to Application/Storage > Cookies"
            echo "4. Copy the cookie values"
            echo ""
            prompt_input "Confluence cookies (format: 'cookie1=value1; cookie2=value2')" confluence_cookies "required"
            prompt_input "Jira cookies (format: 'cookie1=value1; cookie2=value2')" jira_cookies "required"
            ;;
        2)
            echo "Please provide your authorization headers:"
            prompt_input "Confluence Authorization header (e.g., 'Bearer token' or 'Basic base64')" confluence_auth "required"
            prompt_input "Jira Authorization header (e.g., 'Bearer token' or 'Basic base64')" jira_auth "required"
            ;;
        3)
            echo "⚠️  Browser session mode selected."
            echo "Make sure you're logged into both Confluence and Jira in your default browser."
            confluence_cookies=""
            jira_cookies=""
            confluence_auth=""
            jira_auth=""
            ;;
        *)
            echo "Invalid option. Defaulting to browser session mode."
            confluence_cookies=""
            jira_cookies=""
            confluence_auth=""
            jira_auth=""
            ;;
    esac
}

# Collect user inputs interactively
echo "Please provide the following information:"
echo ""

# Confluence page URL
while true; do
    prompt_input "Confluence page URL" confluence_url "required"
    if validate_url "$confluence_url"; then
        break
    else
        echo "Please enter a valid URL (starting with http:// or https://)"
    fi
done

# Jira server info
prompt_input "Jira server URL (e.g., https://your-company.atlassian.net)" jira_server "required"
while ! validate_url "$jira_server"; do
    echo "Please enter a valid Jira server URL"
    prompt_input "Jira server URL" jira_server "required"
done

# Get authentication info
get_sso_auth

# Optional: Dry run mode
echo ""
read -p "Do you want to run in dry-run mode (preview only, no actual tickets created)? (y/N): " dry_run
if [[ "$dry_run" =~ ^[Yy]$ ]]; then
    DRY_RUN=true
    echo "Running in DRY-RUN mode - no tickets will be created"
else
    DRY_RUN=false
    echo "Running in LIVE mode - tickets will be created"
fi

echo ""
echo "Configuration Summary:"
echo "Confluence URL: $confluence_url"
echo "Jira Server: $jira_server"
echo "Dry Run Mode: $DRY_RUN"
echo ""

read -p "Do you want to proceed? (y/N): " proceed
if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo ""
echo "=========================================="
echo "Step 1: Fetching Confluence page..."
echo "=========================================="

# Create temporary file for HTML content
temp_html=$(mktemp)
temp_table=$(mktemp)

echo "Fetching page: $confluence_url"

# Build curl command based on authentication method
if [ -n "$confluence_cookies" ]; then
    curl_auth_confluence="-H 'Cookie: $confluence_cookies'"
elif [ -n "$confluence_auth" ]; then
    curl_auth_confluence="-H 'Authorization: $confluence_auth'"
else
    curl_auth_confluence="--cookie-jar /tmp/cookies --cookie /tmp/cookies"
fi

# Fetch Confluence page
if eval "curl -s -L $curl_auth_confluence '$confluence_url' > '$temp_html'"; then
    echo "✅ Successfully fetched Confluence page"
    
    # Check if we got actual content (not a login redirect)
    if grep -q "login" "$temp_html" && ! grep -q "<table" "$temp_html"; then
        echo "❌ Authentication failed - got redirected to login page"
        echo "Please check your SSO session and authentication details"
        rm -f "$temp_html" "$temp_table"
        exit 1
    fi
else
    echo "❌ Failed to fetch Confluence page"
    rm -f "$temp_html" "$temp_table"
    exit 1
fi

echo ""
echo "=========================================="
echo "Step 2: Parsing table data..."
echo "=========================================="

# Extract table from HTML and parse rows
echo "Parsing table with columns: Title, Start, End, # of ppl involved, Comments, Resolution, Next steps, On Call required SME"

# Use awk to extract table rows (skipping header)
awk '
/<table/,/<\/table>/ {
    if (/<tr/) {
        in_row = 1
        row = ""
        cells = 0
    }
    if (in_row && /<td/) {
        gsub(/<[^>]*>/, "", $0)  # Remove HTML tags
        gsub(/^[ \t]+|[ \t]+$/, "", $0)  # Trim whitespace
        if ($0 != "") {
            if (cells > 0) row = row "|"
            row = row $0
            cells++
        }
    }
    if (/<\/tr>/ && in_row) {
        if (cells >= 8 && NR > first_row) {  # Skip header row, ensure we have all columns
            print row
        }
        if (cells >= 8 && !first_row) first_row = NR  # Mark first data row
        in_row = 0
    }
}' "$temp_html" > "$temp_table"

# Count the number of rows found
row_count=$(wc -l < "$temp_table")
echo "Found $row_count data rows in the table"

if [ "$row_count" -eq 0 ]; then
    echo "❌ No table data found. Please check:"
    echo "  - The Confluence page contains a table"
    echo "  - Your authentication is working correctly"
    echo "  - The table has the expected 8 columns"
    rm -f "$temp_html" "$temp_table"
    exit 1
fi

echo ""
echo "Preview of parsed data:"
echo "----------------------------------------"
head -3 "$temp_table" | nl
if [ "$row_count" -gt 3 ]; then
    echo "... and $((row_count - 3)) more rows"
fi

echo ""
echo "=========================================="
echo "Step 3: Creating Jira tickets..."
echo "=========================================="

# Function to create Jira ticket
create_jira_ticket() {
    local title="$1"
    local start="$2"
    local end="$3"
    local people_involved="$4"
    local comments="$5"
    local resolution="$6"
    local next_steps="$7"
    local sme_required="$8"
    
    # Build Jira ticket description
    local description="*Confluence Link:* $confluence_url

*Start:* $start
*End:* $end
*Number of people involved:* $people_involved
*Comments:* $comments
*Resolution:* $resolution
*Next steps:* $next_steps
*On Call required SME:* $sme_required"

    if [ "$DRY_RUN" = true ]; then
        echo "🔍 DRY-RUN: Would create ticket:"
        echo "  Project: PDMSUPPORT"
        echo "  Type: Bug"
        echo "  Summary: $title"
        echo "  Description: [truncated for display]"
        echo ""
        return 0
    else
        echo "🎫 Creating Jira ticket: $title"
        
        # Prepare JSON payload
        local json_payload=$(cat <<EOF
{
  "fields": {
    "project": {"key": "PDMSUPPORT"},
    "issuetype": {"name": "Bug"},
    "summary": "$title",
    "description": {
      "type": "doc",
      "version": 1,
      "content": [
        {
          "type": "paragraph",
          "content": [
            {
              "type": "text",
              "text": "$description"
            }
          ]
        }
      ]
    }
  }
}
EOF
)
        
        # Build curl command for Jira
        if [ -n "$jira_cookies" ]; then
            curl_auth_jira="-H 'Cookie: $jira_cookies'"
        elif [ -n "$jira_auth" ]; then
            curl_auth_jira="-H 'Authorization: $jira_auth'"
        else
            curl_auth_jira="--cookie-jar /tmp/cookies --cookie /tmp/cookies"
        fi
        
        # Create Jira ticket
        local response=$(eval "curl -s -X POST $curl_auth_jira -H 'Content-Type: application/json' -H 'Accept: application/json' '$jira_server/rest/api/3/issue' -d '$json_payload'")
        
        # Parse response
        if echo "$response" | grep -q '"key"'; then
            local ticket_key=$(echo "$response" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
            echo "✅ Created ticket: $ticket_key"
            echo "   Summary: $title"
            echo "   URL: $jira_server/browse/$ticket_key"
            created_tickets+=("$ticket_key")
        else
            echo "❌ Failed to create ticket: $title"
            echo "   Error response: $response"
            failed_tickets+=("$title")
        fi
        echo ""
    fi
}

# Initialize counters
created_tickets=()
failed_tickets=()

# Process each row from the table
row_num=1
while IFS='|' read -r title start end people_involved comments resolution next_steps sme_required; do
    echo "Processing row $row_num of $row_count..."
    
    # Clean up any remaining HTML entities or special characters
    title=$(echo "$title" | sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g')
    
    create_jira_ticket "$title" "$start" "$end" "$people_involved" "$comments" "$resolution" "$next_steps" "$sme_required"
    
    ((row_num++))
    
    # Small delay to be nice to the API
    sleep 1
    
done < "$temp_table"

# Cleanup temporary files
rm -f "$temp_html" "$temp_table"

echo ""
echo "=========================================="
echo "Process completed!"
echo "=========================================="

echo ""
echo "📊 SUMMARY:"
if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN completed - $row_count tickets would have been created"
else
    echo "Created tickets: ${#created_tickets[@]}"
    echo "Failed tickets: ${#failed_tickets[@]}"
    echo "Total processed: $row_count"
    
    if [ ${#created_tickets[@]} -gt 0 ]; then
        echo ""
        echo "✅ Successfully created tickets:"
        printf '   %s\n' "${created_tickets[@]}"
    fi
    
    if [ ${#failed_tickets[@]} -gt 0 ]; then
        echo ""
        echo "❌ Failed to create tickets for:"
        printf '   %s\n' "${failed_tickets[@]}"
    fi
fi
