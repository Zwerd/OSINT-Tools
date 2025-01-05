#!/bin/bash

# Colors and styles for formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'  # No Color (reset)

# Check if the user has provided the DNS file as an argument
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: No DNS file provided! Please provide a DNS file.<${NC}"
    exit 1
fi

# File containing the list of DNS servers
dns_file="$1"

# Domain to query
domain="pmo.gov.il"

# Check if the DNS file exists
if [ ! -f "$dns_file" ]; then
    echo -e "${RED}Error: DNS file '$dns_file' not found!${NC}"
    exit 1
fi

# Read each DNS server from the file and check if it's active
while IFS= read -r dns_server; do
    # Skip empty lines or comments (if any)
    if [[ -z "$dns_server" || "$dns_server" =~ ^# ]]; then
        continue
    fi

    echo -e "${BOLD}Checking DNS server: $dns_server...${NC}"

    # Use dig to query the DNS server for the domain
    dig @$dns_server $domain +short > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}DNS server $dns_server is ACTIVE and responding to queries.${NC}"
    else
        echo -e "${RED}DNS server $dns_server is INACTIVE or not responding to queries.${NC}"
    fi

    echo -e "${YELLOW}----------------------------------------${NC}"
done < "$dns_file"
