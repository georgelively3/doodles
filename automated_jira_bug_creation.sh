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

# Function to get authentication credentials
get_auth_credentials() {
    echo ""
    echo "=========================================="
    echo "Authentication Setup"
    echo "=========================================="
    echo "Please provide your corporate login credentials:"
    echo ""
    
    prompt_input "Username (your corporate login)" username "required"
    
    # Read password securely (without echoing to screen)
    echo -n "Password: "
    read -s password
    echo ""  # Add newline after password input
    
    if [ -z "$password" ]; then
        echo "Password cannot be empty. Please try again."
        get_auth_credentials
        return
    fi
    
    echo "✅ Credentials captured"
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

# Normalize Jira URL - remove trailing slashes and ensure it's just the base URL
jira_server=$(echo "$jira_server" | sed 's|/$||' | sed 's|/rest/api/.*||')

# Get authentication info
get_auth_credentials

# Build authentication header (used for both Confluence and Jira)
auth_header="Authorization: Basic $(echo -n "$username:$password" | base64)"

# Test Jira connection
echo ""
echo "=========================================="
echo "Testing Jira Connection..."
echo "=========================================="

echo "Testing Jira API connection..."
jira_test_url="$jira_server/rest/api/2/myself"
echo "Testing URL: $jira_test_url"

jira_test_response=$(curl -s -w "HTTP_CODE:%{http_code}" -H "$auth_header" "$jira_test_url")
jira_http_code=$(echo "$jira_test_response" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
jira_content=$(echo "$jira_test_response" | sed 's/HTTP_CODE:[0-9]*$//')

echo "HTTP Response Code: $jira_http_code"

case "$jira_http_code" in
    200)
        echo "✅ Jira authentication successful!"
        jira_user=$(echo "$jira_content" | grep -o '"displayName":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$jira_user" ]; then
            echo "   Logged in as: $jira_user"
        fi
        ;;
    401)
        echo "❌ Jira authentication failed (401 Unauthorized)"
        echo "   Please check your username and password for Jira access"
        echo "   Note: Jira may have different credentials than Confluence"
        exit 1
        ;;
    403)
        echo "❌ Jira access forbidden (403 Forbidden)"
        echo "   Your account may not have permission to access Jira API"
        exit 1
        ;;
    404)
        echo "❌ Jira API endpoint not found (404)"
        echo "   Please verify the Jira server URL: $jira_server"
        echo "   Try variations like:"
        echo "   - $jira_server (if it's Jira Cloud)"
        echo "   - $jira_server:8080 (if it's Jira Server on port 8080)"
        exit 1
        ;;
    *)
        echo "❌ Unexpected response from Jira (HTTP $jira_http_code)"
        echo "   Response: $jira_content"
        echo "   Please check the Jira server URL and try again"
        exit 1
        ;;
esac

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
echo "Username: $username"
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

# Fetch Confluence page
if curl -s -L -H "$auth_header" "$confluence_url" > "$temp_html"; then
    echo "✅ Successfully fetched Confluence page"
    
    # Get file size for debugging
    file_size=$(wc -c < "$temp_html")
    echo "📄 Page content size: $file_size bytes"
    
    # Check if we got actual content (not a login redirect)
    if grep -q "login" "$temp_html" && ! grep -q "<table" "$temp_html"; then
        echo "❌ Authentication failed - got redirected to login page"
        echo "Please check your username and password"
        rm -f "$temp_html" "$temp_table"
        exit 1
    fi
    
    # Debug: Check what kind of content we received
    echo "🔍 Content analysis:"
    
    # Check for common Confluence indicators
    if grep -q "confluence" "$temp_html"; then
        echo "  ✅ Confluence content detected"
    else
        echo "  ⚠️  No obvious Confluence markers found"
    fi
    
    # Check for authentication success
    if grep -q "sign.*in\|log.*in\|unauthorized\|access.*denied" "$temp_html"; then
        echo "  ❌ Possible authentication issue detected"
    else
        echo "  ✅ No authentication errors detected"
    fi
    
    # Check for frames/iframes
    if grep -q "<iframe\|<frame" "$temp_html"; then
        echo "  ⚠️  Frames/iframes detected - this may complicate table extraction"
        iframe_count=$(grep -c "<iframe" "$temp_html")
        echo "    Found $iframe_count iframe(s)"
        
        # Try to extract iframe sources
        echo "    Iframe sources found:"
        grep -o 'src="[^"]*"' "$temp_html" | head -5 | sed 's/^/      /'
    else
        echo "  ✅ No frames detected"
    fi
    
    # Check for tables
    table_count=$(grep -c "<table" "$temp_html")
    echo "  📊 Found $table_count table(s) in main content"
    
    if [ "$table_count" -eq 0 ]; then
        echo "  ❌ No tables found in main page content"
        echo "  💡 This could be due to:"
        echo "     - Content in iframes/frames"
        echo "     - Dynamic content loaded by JavaScript"
        echo "     - Tables in embedded views"
    else
        echo "  ✅ Tables found in content"
        
        # Show table structure info
        echo "  📋 Table analysis:"
        awk '/<table/,/<\/table>/ {
            if (/<table/) table_start = NR
            if (/<tr/) tr_count++
            if (/<th/) th_count++
            if (/<td/) td_count++
            if (/<\/table>/) {
                print "    Table at line " table_start ": " tr_count " rows, " th_count " headers, " td_count " cells"
                tr_count = 0; th_count = 0; td_count = 0
            }
        }' "$temp_html"
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

# Function to try extracting tables from iframe sources
try_iframe_tables() {
    echo "🔍 Attempting to extract tables from iframes..."
    
    # Extract iframe sources and try each one
    grep -o 'src="[^"]*"' "$temp_html" | cut -d'"' -f2 | while read -r iframe_src; do
        # Skip if it's not a full URL
        if [[ "$iframe_src" =~ ^https?:// ]] || [[ "$iframe_src" =~ ^/ ]]; then
            # Convert relative URLs to absolute
            if [[ "$iframe_src" =~ ^/ ]]; then
                base_url=$(echo "$confluence_url" | sed 's|^\(https\?://[^/]*\).*|\1|')
                iframe_url="$base_url$iframe_src"
            else
                iframe_url="$iframe_src"
            fi
            
            echo "  📄 Trying iframe: $iframe_url"
            
            # Create temp file for iframe content
            temp_iframe=$(mktemp)
            
            if curl -s -L -H "$auth_header" "$iframe_url" > "$temp_iframe"; then
                iframe_tables=$(grep -c "<table" "$temp_iframe")
                if [ "$iframe_tables" -gt 0 ]; then
                    echo "    ✅ Found $iframe_tables table(s) in iframe"
                    # Try to parse this iframe's tables
                    if parse_tables_from_file "$temp_iframe" > "$temp_table"; then
                        iframe_rows=$(wc -l < "$temp_table")
                        if [ "$iframe_rows" -gt 0 ]; then
                            echo "    🎯 Successfully extracted $iframe_rows rows from iframe!"
                            rm -f "$temp_iframe"
                            return 0
                        fi
                    fi
                else
                    echo "    ❌ No tables in this iframe"
                fi
            else
                echo "    ❌ Failed to fetch iframe content"
            fi
            
            rm -f "$temp_iframe"
        fi
    done
    
    return 1
}

# Function to parse tables from a file
parse_tables_from_file() {
    local file="$1"
    
    # Enhanced awk script for better table parsing
    awk '
    BEGIN { 
        in_table = 0
        in_row = 0
        skip_header = 1
    }
    /<table/ { 
        in_table = 1
        print "<!-- Table found -->" > "/dev/stderr"
    }
    /<\/table>/ { 
        in_table = 0 
        skip_header = 1
    }
    in_table && /<tr/ {
        in_row = 1
        row = ""
        cells = 0
        cell_content = ""
    }
    in_table && in_row && /<t[hd]/ {
        # Extract cell content, handling nested tags
        cell_line = $0
        gsub(/<t[hd][^>]*>/, "", cell_line)  # Remove opening tags
        gsub(/<\/t[hd]>/, "|CELL_END|", cell_line)  # Mark cell endings
        gsub(/<[^>]*>/, "", cell_line)  # Remove other HTML tags
        gsub(/&nbsp;/, " ", cell_line)  # Convert HTML entities
        gsub(/&amp;/, "\\&", cell_line)
        gsub(/&lt;/, "<", cell_line)
        gsub(/&gt;/, ">", cell_line)
        gsub(/&quot;/, "\"", cell_line)
        
        # Split by cell markers and process
        split(cell_line, cell_parts, /\|CELL_END\|/)
        for (i in cell_parts) {
            if (cell_parts[i] != "") {
                gsub(/^[ \t\n\r]+|[ \t\n\r]+$/, "", cell_parts[i])  # Trim
                if (cell_parts[i] != "") {
                    if (cells > 0) row = row "|"
                    row = row cell_parts[i]
                    cells++
                }
            }
        }
    }
    in_table && /<\/tr>/ && in_row {
        if (cells >= 8) {
            if (skip_header) {
                print "<!-- Skipping header row: " cells " cells -->" > "/dev/stderr"
                skip_header = 0
            } else {
                print row
                print "<!-- Data row: " cells " cells -->" > "/dev/stderr"
            }
        } else if (cells > 0) {
            print "<!-- Row with " cells " cells (need 8): " row " -->" > "/dev/stderr"
        }
        in_row = 0
    }
    ' "$file" 2>"${file}.debug"
}

# Extract table from HTML and parse rows
echo "Parsing table with columns: Title, Start, End, # of ppl involved, Comments, Resolution, Next steps, On Call required SME"

# First, try parsing tables from main content
echo "🔍 Attempting to parse tables from main page content..."
parse_tables_from_file "$temp_html" > "$temp_table"

# Count the number of rows found
row_count=$(wc -l < "$temp_table")
echo "Found $row_count data rows in main content"

# If no rows found and we detected iframes, try iframe content
if [ "$row_count" -eq 0 ] && grep -q "<iframe" "$temp_html"; then
    echo ""
    echo "🔄 No data in main content, trying iframe sources..."
    if try_iframe_tables; then
        row_count=$(wc -l < "$temp_table")
        echo "✅ Found $row_count rows in iframe content"
    fi
fi

# Enhanced debugging output
if [ "$row_count" -eq 0 ]; then
    echo ""
    echo "❌ No table data found. Detailed diagnosis:"
    echo ""
    
    # Show debug info from table parsing
    if [ -f "${temp_html}.debug" ]; then
        echo "🔍 Table parsing debug info:"
        cat "${temp_html}.debug" | head -10
        echo ""
    fi
    
    echo "📋 Troubleshooting checklist:"
    echo "  1. ✅ Authentication: $(if grep -q "sign.*in\|log.*in" "$temp_html"; then echo "❌ Failed"; else echo "✅ Working"; fi)"
    echo "  2. ✅ Page content: $(if [ $(wc -c < "$temp_html") -lt 1000 ]; then echo "❌ Too small"; else echo "✅ Adequate size"; fi)"
    echo "  3. ✅ Tables present: $(if [ $(grep -c "<table" "$temp_html") -gt 0 ]; then echo "✅ Found"; else echo "❌ None found"; fi)"
    echo "  4. ✅ Expected columns: Needs manual verification"
    echo "  5. ✅ Iframe content: $(if grep -q "<iframe" "$temp_html"; then echo "⚠️ Detected (tried extraction)"; else echo "✅ Not applicable"; fi)"
    echo ""
    echo "💡 Possible solutions:"
    echo "  - Try a different Confluence URL (direct table view)"
    echo "  - Export the page as Word/PDF and copy table data"
    echo "  - Check if the table is in a restricted view"
    echo "  - Verify the page URL is accessible without login"
    
    # Offer to save debug files
    echo ""
    read -p "Save debug files for manual inspection? (y/N): " save_debug
    if [[ "$save_debug" =~ ^[Yy]$ ]]; then
        debug_dir="debug_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$debug_dir"
        cp "$temp_html" "$debug_dir/page_content.html"
        if [ -f "${temp_html}.debug" ]; then
            cp "${temp_html}.debug" "$debug_dir/table_parsing.log"
        fi
        echo "Debug files saved to: $debug_dir/"
        echo "You can open page_content.html in a browser to inspect the structure"
    fi
    
    rm -f "$temp_html" "$temp_table" "${temp_html}.debug"
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
        
        # Prepare JSON payload (using API v2 format for broader compatibility)
        local json_payload=$(cat <<EOF
{
  "fields": {
    "project": {"key": "PDMSUPPORT"},
    "issuetype": {"name": "Bug"},
    "summary": "$title",
    "description": "$description"
  }
}
EOF
)
        
        # Create Jira ticket using API v2
        local response=$(curl -s -w "HTTP_CODE:%{http_code}" -X POST \
            -H "$auth_header" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            "$jira_server/rest/api/2/issue" \
            -d "$json_payload")
        
        # Extract HTTP code and content
        local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
        local response_content=$(echo "$response" | sed 's/HTTP_CODE:[0-9]*$//')
        
        # Parse response with detailed error handling
        case "$http_code" in
            201)
                if echo "$response_content" | grep -q '"key"'; then
                    local ticket_key=$(echo "$response_content" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
                    echo "✅ Created ticket: $ticket_key"
                    echo "   Summary: $title"
                    echo "   URL: $jira_server/browse/$ticket_key"
                    created_tickets+=("$ticket_key")
                else
                    echo "❌ Ticket creation succeeded but couldn't parse ticket key"
                    echo "   Response: $response_content"
                    failed_tickets+=("$title")
                fi
                ;;
            400)
                echo "❌ Bad request (400) - Invalid ticket data: $title"
                if echo "$response_content" | grep -q "project"; then
                    echo "   Check: Project 'PDMSUPPORT' exists and you have access"
                fi
                if echo "$response_content" | grep -q "issuetype"; then
                    echo "   Check: Issue type 'Bug' is available in the project"
                fi
                echo "   Full error: $response_content"
                failed_tickets+=("$title")
                ;;
            401)
                echo "❌ Authentication failed (401) for ticket: $title"
                echo "   Your session may have expired"
                failed_tickets+=("$title")
                ;;
            403)
                echo "❌ Permission denied (403) for ticket: $title"
                echo "   You may not have permission to create issues in project PDMSUPPORT"
                failed_tickets+=("$title")
                ;;
            *)
                echo "❌ Failed to create ticket (HTTP $http_code): $title"
                echo "   Error response: $response_content"
                failed_tickets+=("$title")
                ;;
        esac
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
rm -f "$temp_html" "$temp_table" "${temp_html}.debug"

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
# end at 3:25 9/22
