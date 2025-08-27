#!/bin/bash

# API Connection Script with Table Formatting
# Connects to OEM Manager API and displays results in a formatted table

# Configuration
HOST="10.1.11.22"
INSTANCEPORT="11240"
USER="tomcat"
PASS="tomcat"
URL="http://$HOST:$INSTANCEPORT/oemanager/applications/pasEsbPrice/agents/sessions"
TEMP_FILE="/tmp/api_response.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Connecting to OEM Manager API...${NC}"
echo "URL: $URL"
echo "User: $USER"
echo ""

# Make the API call with basic authentication using -sk flags
response=$(curl -sk -u "$USER:$PASS" "$URL" -w "HTTPSTATUS:%{http_code}" 2>/dev/null)

# Extract HTTP status code
http_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
response_body=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]*$//')

# Check HTTP status
if [ "$http_code" != "200" ]; then
    echo -e "${RED}Error: HTTP $http_code${NC}"
    echo "Response: $response_body"
    exit 1
fi

echo -e "${GREEN}Connection successful!${NC}"
echo ""

# Save response to temp file for processing
echo "$response_body" > "$TEMP_FILE"

# Check if response is valid JSON
if ! jq empty "$TEMP_FILE" 2>/dev/null; then
    echo -e "${YELLOW}Warning: Response is not valid JSON${NC}"
    echo "Raw response:"
    echo "$response_body"
    exit 1
fi

# Function to create beautiful table borders
print_border() {
    local width=$1
    local char=$2
    printf "%*s\n" $width | tr ' ' "$char"
}

# Function to print a formatted row
print_row() {
    local cols=("$@")
    local col_widths=(25 20 15 20 30 25)  # Adjust column widths as needed
    
    printf "│"
    for i in "${!cols[@]}"; do
        if [ $i -lt ${#col_widths[@]} ]; then
            printf " %-${col_widths[$i]}s │" "${cols[$i]}"
        else
            printf " %-20s │" "${cols[$i]}"
        fi
    done
    printf "\n"
}

# Function to format memory values in human readable format
format_memory() {
    local bytes=$1
    if [ "$bytes" -eq 0 ]; then
        echo "0 B"
    elif [ "$bytes" -lt 1024 ]; then
        echo "${bytes} B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$(( bytes / 1024 )) KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$(( bytes / 1048576 )) MB"
    else
        echo "$(( bytes / 1073741824 )) GB"
    fi
}

# Function to format date/time
format_datetime() {
    local datetime=$1
    if [ "$datetime" = "null" ] || [ -z "$datetime" ]; then
        echo "N/A"
    else
        # Extract just the date and time part, remove timezone
        echo "$datetime" | sed 's/\+.*$//' | sed 's/T/ /'
    fi
}

# Function to create dynamic table based on JSON structure
create_beautiful_table() {
    local data_file=$1
    
    # Check if this is an OEM Manager response structure
    if jq -e '.result.agents' "$data_file" >/dev/null 2>&1; then
        # Handle OEM Manager specific structure
        local agent_count
        local total_sessions
        local version
        
        agent_count=$(jq '.result.agents | length' "$data_file")
        total_sessions=$(jq '[.result.agents[].sessions[]] | length' "$data_file")
        version=$(jq -r '.versionStr // "Unknown"' "$data_file")
        
        echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║${NC}                                                          ${YELLOW}OEM MANAGER - AGENT SESSIONS REPORT${NC}                                                                      ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}                                        ${GREEN}Agents: $agent_count${NC}  |  ${GREEN}Total Sessions: $total_sessions${NC}  |  ${GREEN}Version: $version${NC}                                            ${BLUE}║${NC}"
        echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # Process each agent
        jq -c '.result.agents[]' "$data_file" | while read -r agent; do
            local agent_id
            local agent_pid
            local agent_state
            local agent_start_time
            local overhead_memory
            local session_count
            
            agent_id=$(echo "$agent" | jq -r '.agentId')
            agent_pid=$(echo "$agent" | jq -r '.pid')
            agent_state=$(echo "$agent" | jq -r '.state')
            agent_start_time=$(echo "$agent" | jq -r '.agentStartTime')
            overhead_memory=$(echo "$agent" | jq -r '.overheadMemory')
            session_count=$(echo "$agent" | jq '.sessions | length')
            
            # Format values
            formatted_start_time=$(format_datetime "$agent_start_time")
            formatted_overhead=$(format_memory "$overhead_memory")
            
            # Agent header
            echo -e "${YELLOW}┌─ AGENT: ${agent_id:0:20}... ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐${NC}"
            echo -e "${YELLOW}│${NC} PID: ${BLUE}$agent_pid${NC}  |  State: ${GREEN}$agent_state${NC}  |  Started: ${formatted_start_time}  |  Overhead: ${formatted_overhead}  |  Sessions: ${session_count} ${YELLOW}│${NC}"
            echo -e "${YELLOW}└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘${NC}"
            echo ""
            
            # Sessions table
            local sessions
            sessions=$(echo "$agent" | jq '.sessions')
            
            if [ "$(echo "$sessions" | jq 'length')" -gt 0 ]; then
                # Table header
                printf "┌─────────────┬─────────────┬──────────────────────┬─────────────┬─────────────┬─────────────┬──────────────┬──────────────┬──────────────┐\n"
                printf "│ ${YELLOW}%-11s${NC} │ ${YELLOW}%-11s${NC} │ ${YELLOW}%-20s${NC} │ ${YELLOW}%-11s${NC} │ ${YELLOW}%-11s${NC} │ ${YELLOW}%-11s${NC} │ ${YELLOW}%-12s${NC} │ ${YELLOW}%-12s${NC} │ ${YELLOW}%-12s${NC} │\n" "Session ID" "State" "Start Time" "Completed" "Failed" "Memory" "Mem@Rest HW" "Mem Active HW" "Thread/Conn"
                printf "├─────────────┼─────────────┼──────────────────────┼─────────────┼─────────────┼─────────────┼──────────────┼──────────────┼──────────────┤\n"
                
                # Process each session
                echo "$sessions" | jq -c '.[]' | while read -r session; do
                    local session_id session_state start_time requests_completed requests_failed
                    local session_memory mem_rest_hw mem_active_hw thread_id connection_id
                    
                    session_id=$(echo "$session" | jq -r '.SessionId')
                    session_state=$(echo "$session" | jq -r '.SessionState')
                    start_time=$(echo "$session" | jq -r '.StartTime')
                    requests_completed=$(echo "$session" | jq -r '.RequestsCompleted')
                    requests_failed=$(echo "$session" | jq -r '.RequestsFailed')
                    session_memory=$(echo "$session" | jq -r '.SessionMemory')
                    mem_rest_hw=$(echo "$session" | jq -r '.MemAtRestHighWater')
                    mem_active_hw=$(echo "$session" | jq -r '.MemActiveHighWater')
                    thread_id=$(echo "$session" | jq -r '.ThreadId')
                    connection_id=$(echo "$session" | jq -r '.ConnectionId')
                    
                    # Format values
                    formatted_start=$(format_datetime "$start_time")
                    formatted_session_mem=$(format_memory "$session_memory")
                    formatted_rest_hw=$(format_memory "$mem_rest_hw")
                    formatted_active_hw=$(format_memory "$mem_active_hw")
                    
                    # Format thread/connection display
                    local thread_conn_display="T:$thread_id/C:$connection_id"
                    if [ "$thread_id" = "-1" ] && [ "$connection_id" = "-1" ]; then
                        thread_conn_display="N/A"
                    fi
                    
                    # Color code session state
                    local state_color=""
                    local state_reset=""
                    if [ "$session_state" = "IDLE" ]; then
                        state_color="${GREEN}"
                        state_reset="${NC}"
                    elif [ "$session_state" = "ACTIVE" ]; then
                        state_color="${BLUE}"
                        state_reset="${NC}"
                    else
                        state_color="${YELLOW}"
                        state_reset="${NC}"
                    fi
                    
                    # Color code failed requests
                    local failed_color=""
                    local failed_reset=""
                    if [ "$requests_failed" -gt 0 ]; then
                        failed_color="${RED}"
                        failed_reset="${NC}"
                    fi
                    
                    printf "│ ${BLUE}%-11s${NC} │ ${state_color}%-11s${state_reset} │ %-20s │ %-11s │ ${failed_color}%-11s${failed_reset} │ %-11s │ %-12s │ %-12s │ %-12s │\n" \
                        "$session_id" "$session_state" "${formatted_start:0:20}" "$requests_completed" "$requests_failed" \
                        "${formatted_session_mem:0:11}" "${formatted_rest_hw:0:12}" "${formatted_active_hw:0:12}" "${thread_conn_display:0:12}"
                done
                
                printf "└─────────────┴─────────────┴──────────────────────┴─────────────┴─────────────┴─────────────┴──────────────┴──────────────┴──────────────┘\n"
                echo ""
            else
                echo -e "${YELLOW}No sessions found for this agent.${NC}"
                echo ""
            fi
        done
        
        # Summary statistics
        echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║${NC}                                                                    ${YELLOW}SUMMARY STATISTICS${NC}                                                                                  ${BLUE}║${NC}"
        echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
        
        local total_requests_completed total_requests_failed total_memory_usage
        total_requests_completed=$(jq '[.result.agents[].sessions[].RequestsCompleted] | add' "$data_file")
        total_requests_failed=$(jq '[.result.agents[].sessions[].RequestsFailed] | add' "$data_file")
        total_memory_usage=$(jq '[.result.agents[].sessions[].SessionMemory] | add' "$data_file")
        
        printf "┌────────────────────────┬─────────────────────────┬─────────────────────────┬─────────────────────────┐\n"
        printf "│ ${YELLOW}%-22s${NC} │ ${YELLOW}%-23s${NC} │ ${YELLOW}%-23s${NC} │ ${YELLOW}%-23s${NC} │\n" "Total Agents" "Total Requests" "Failed Requests" "Total Memory Usage"
        printf "├────────────────────────┼─────────────────────────┼─────────────────────────┼─────────────────────────┤\n"
        printf "│ ${GREEN}%-22s${NC} │ ${GREEN}%-23s${NC} │ ${RED}%-23s${NC} │ ${BLUE}%-23s${NC} │\n" \
            "$agent_count" "$total_requests_completed" "$total_requests_failed" "$(format_memory "$total_memory_usage")"
        printf "└────────────────────────┴─────────────────────────┴─────────────────────────┴─────────────────────────┘\n"
        
    elif jq -e 'type == "array"' "$data_file" >/dev/null 2>&1; then
        # Handle array response
        local count=$(jq 'length' "$data_file")
        
        echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║${NC}                                           ${YELLOW}OEM MANAGER - AGENT SESSIONS${NC}                                                    ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}                                              ${GREEN}Total Sessions: $count${NC}                                                        ${BLUE}║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        if [ "$count" -eq 0 ]; then
            echo -e "${YELLOW}No active sessions found.${NC}"
            return
        fi
        
        # Get all unique keys for headers
        local headers
        headers=$(jq -r '[.[] | keys] | flatten | unique | @json' "$data_file" | jq -r '.[]')
        
        # Convert headers to array
        local header_array=()
        while IFS= read -r header; do
            header_array+=("$header")
        done < <(echo "$headers")
        
        # Calculate dynamic column widths based on content
        local col_widths=()
        for header in "${header_array[@]}"; do
            local max_width=${#header}
            local content_width
            content_width=$(jq -r ".[] | .$header | tostring | length" "$data_file" | sort -rn | head -1)
            if [ "$content_width" -gt "$max_width" ]; then
                max_width=$content_width
            fi
            # Cap maximum width and ensure minimum width
            if [ "$max_width" -lt 12 ]; then max_width=12; fi
            if [ "$max_width" -gt 35 ]; then max_width=35; fi
            col_widths+=($max_width)
        done
        
        # Calculate total table width
        local total_width=1
        for width in "${col_widths[@]}"; do
            total_width=$((total_width + width + 3))
        done
        
        # Print table header
        printf "┌"
        for i in "${!col_widths[@]}"; do
            printf "%*s" $((${col_widths[$i]} + 2)) | tr ' ' '─'
            if [ $i -lt $((${#col_widths[@]} - 1)) ]; then
                printf "┬"
            fi
        done
        printf "┐\n"
        
        # Print header row
        printf "│"
        for i in "${!header_array[@]}"; do
            printf " ${YELLOW}%-${col_widths[$i]}s${NC} │" "${header_array[$i]}"
        done
        printf "\n"
        
        # Print separator
        printf "├"
        for i in "${!col_widths[@]}"; do
            printf "%*s" $((${col_widths[$i]} + 2)) | tr ' ' '─'
            if [ $i -lt $((${#col_widths[@]} - 1)) ]; then
                printf "┼"
            fi
        done
        printf "┤\n"
        
        # Print data rows
        local row_num=0
        jq -c '.[]' "$data_file" | while read -r row; do
            row_num=$((row_num + 1))
            printf "│"
            for i in "${!header_array[@]}"; do
                local value
                value=$(echo "$row" | jq -r ".${header_array[$i]} // \"N/A\" | tostring")
                
                # Truncate if too long
                if [ ${#value} -gt ${col_widths[$i]} ]; then
                    value="${value:0:$((${col_widths[$i]} - 3))}..."
                fi
                
                # Color coding for specific fields
                if [[ "${header_array[$i]}" == *"status"* ]] || [[ "${header_array[$i]}" == *"state"* ]]; then
                    if [[ "$value" == *"active"* ]] || [[ "$value" == *"running"* ]] || [[ "$value" == *"connected"* ]]; then
                        printf " ${GREEN}%-${col_widths[$i]}s${NC} │" "$value"
                    elif [[ "$value" == *"inactive"* ]] || [[ "$value" == *"stopped"* ]] || [[ "$value" == *"disconnected"* ]]; then
                        printf " ${RED}%-${col_widths[$i]}s${NC} │" "$value"
                    else
                        printf " ${YELLOW}%-${col_widths[$i]}s${NC} │" "$value"
                    fi
                elif [[ "${header_array[$i]}" == *"id"* ]] || [[ "${header_array[$i]}" == *"ID"* ]]; then
                    printf " ${BLUE}%-${col_widths[$i]}s${NC} │" "$value"
                else
                    printf " %-${col_widths[$i]}s │" "$value"
                fi
            done
            printf "\n"
        done
        
        # Print table footer
        printf "└"
        for i in "${!col_widths[@]}"; do
            printf "%*s" $((${col_widths[$i]} + 2)) | tr ' ' '─'
            if [ $i -lt $((${#col_widths[@]} - 1)) ]; then
                printf "┴"
            fi
        done
        printf "┘\n"
        
    elif jq -e 'type == "object"' "$data_file" >/dev/null 2>&1; then
        # Handle single object response
        echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║${NC}                           ${YELLOW}SESSION DETAILS${NC}                                ${BLUE}║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # Get the maximum key length for proper formatting
        local max_key_length
        max_key_length=$(jq -r 'keys[] | length' "$data_file" | sort -rn | head -1)
        if [ "$max_key_length" -lt 20 ]; then max_key_length=20; fi
        
        local max_value_length=60
        local total_width=$((max_key_length + max_value_length + 7))
        
        # Print table header
        printf "┌"
        printf "%*s" $((max_key_length + 2)) | tr ' ' '─'
        printf "┬"
        printf "%*s" $((max_value_length + 2)) | tr ' ' '─'
        printf "┐\n"
        
        printf "│ ${YELLOW}%-${max_key_length}s${NC} │ ${YELLOW}%-${max_value_length}s${NC} │\n" "Property" "Value"
        
        printf "├"
        printf "%*s" $((max_key_length + 2)) | tr ' ' '─'
        printf "┼"
        printf "%*s" $((max_value_length + 2)) | tr ' ' '─'
        printf "┤\n"
        
        # Print key-value pairs
        jq -r 'to_entries[] | "\(.key)|\(.value | tostring)"' "$data_file" | while IFS='|' read -r key value; do
            # Handle long values
            if [ ${#value} -gt $max_value_length ]; then
                value="${value:0:$((max_value_length - 3))}..."
            fi
            
            # Color coding
            if [[ "$key" == *"status"* ]] || [[ "$key" == *"state"* ]]; then
                if [[ "$value" == *"active"* ]] || [[ "$value" == *"running"* ]]; then
                    printf "│ ${BLUE}%-${max_key_length}s${NC} │ ${GREEN}%-${max_value_length}s${NC} │\n" "$key" "$value"
                else
                    printf "│ ${BLUE}%-${max_key_length}s${NC} │ ${RED}%-${max_value_length}s${NC} │\n" "$key" "$value"
                fi
            elif [[ "$key" == *"id"* ]] || [[ "$key" == *"ID"* ]]; then
                printf "│ ${BLUE}%-${max_key_length}s${NC} │ ${YELLOW}%-${max_value_length}s${NC} │\n" "$key" "$value"
            else
                printf "│ ${BLUE}%-${max_key_length}s${NC} │ %-${max_value_length}s │\n" "$key" "$value"
            fi
        done
        
        # Print table footer
        printf "└"
        printf "%*s" $((max_key_length + 2)) | tr ' ' '─'
        printf "┴"
        printf "%*s" $((max_value_length + 2)) | tr ' ' '─'
        printf "┘\n"
        
    else
        # Handle primitive response
        echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║${NC}                    ${YELLOW}API RESPONSE${NC}                    ${BLUE}║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}$response_body${NC}"
    fi
}

# Create the beautiful table
create_beautiful_table "$TEMP_FILE"

# Cleanup
rm -f "$TEMP_FILE"

echo ""
echo -e "${GREEN}Script completed successfully.${NC}"
