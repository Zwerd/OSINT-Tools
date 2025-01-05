#!/bin/bash

# Define the mail relay domain (like pmo.gov.il)
relay_domain="pmo.gov.il"

# Define color variables
COLOR_GREEN="\e[1;32m"
COLOR_RED="\e[1;31m"
COLOR_YELLOW="\e[1;33m"
COLOR_RESET="\e[0m"

# Function to check if MX record matches pmo.gov.il or its relay servers
check_mx_record() {
  domain=$1
  mx_records=$(dig +short $domain MX)

  # Loop through MX records and check if it matches the relay domain
  for mx in $mx_records; do
    if [[ "$mx" == *"$relay_domain"* ]]; then
      return 0  # Return 0 (success) if it matches the relay domain
    fi
  done

  return 1  # Return 1 (failure) if no match is found
}

# Check if domains.txt exists
if [ ! -f domains.txt ]; then
  echo "domains.txt file not found!"
  exit 1
fi

# Loop through each domain in domains.txt
while IFS= read -r domain; do
  # Skip empty lines or lines starting with a comment
  if [[ -z "$domain" || "$domain" == \#* ]]; then
    continue
  fi
  
  echo "Checking domain: $domain"

  # Check for MX records
  mx_records=$(dig +short $domain MX)
  
  # If there are no MX records, report it in bold yellow
  if [ -z "$mx_records" ]; then
    echo -e "${COLOR_YELLOW}$domain does not have MX records.${COLOR_RESET}"
  else
    other_mx_found=false
    # Check if the domain uses a relay server from pmo.gov.il
    if check_mx_record $domain; then
      # Apply bold and color (green) for domains using pmo.gov.il relay servers
      echo -e "${COLOR_GREEN}$domain uses a relay server from $relay_domain${COLOR_RESET}"
    else
      # Loop through MX records and print any non-pmo records in red bold
      for mx in $mx_records; do
        if [[ "$mx" != *"$relay_domain"* ]]; then
          # If a non-pmo MX record is found, print it in red bold
          echo -e "${COLOR_RED}$domain has MX record $mx that does not use a relay server from $relay_domain${COLOR_RESET}"
          other_mx_found=true
        fi
      done

      # If no non-pmo MX records were found, output normal message
      if ! $other_mx_found; then
        echo "$domain has MX records but does not use a relay server from $relay_domain."
      fi
    fi
  fi

  echo "-----------------------------"
done < domains.txt
