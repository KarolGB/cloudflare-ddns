#!/bin/bash
auth_email=$(cat .secrets/auth_email)
auth_method="token"
auth_key=$(cat .secrets/auth_key)
zone_identifier=$(cat .secrets/zone_identifier)
ttl=300

###########################################
## Get all records from your cloudflare account
###########################################
records=$(curl https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records \
    -H "Authorization: Bearer $auth_key")

###########################################
## Check if we have a public IP
###########################################
ipv4_regex='([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])'
ip=$(curl -s -4 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip'); ret=$?
if [[ ! $ret == 0 ]]; then # In the case that cloudflare failed to return an ip.
    # Attempt to get the ip from other websites.
    ip=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
else
    # Extract just the ip from the ip line from cloudflare.
    ip=$(echo $ip | sed -E "s/^ip=($ipv4_regex)$/\1/")
fi

# Use regex to check for proper IPv4 format.
if [[ ! $ip =~ ^$ipv4_regex$ ]]; then
    logger -s "DDNS Updater: Failed to find a valid IP."
    exit 2
fi

###########################################
## Check and set the proper auth header
###########################################
if [[ "${auth_method}" == "global" ]]; then
  auth_header="X-Auth-Key:"
else
  auth_header="Authorization: Bearer"
fi

###########################################
## Seek for the A record
###########################################

logger "DDNS Updater: Check Initiated"

################################################################
## Loop all A records, for each one get if is proxied and name
################################################################

echo "$records" | jq -c '.result[] | select(.type=="A")' | while read record
do
  record_name=$(jq -r '.name' <<< "$record")
  proxy=$(jq -r '.proxied' <<< "$record")
  record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
                        -H "X-Auth-Email: $auth_email" \
                        -H "$auth_header $auth_key" \
                        -H "Content-Type: application/json")

  ###########################################
  ## Check if the domain has an A record
  ###########################################
  if [[ $record == *"\"count\":0"* ]]; then
    logger -s "DDNS Updater: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
    exit 1
  fi

  ###########################################
  ## Get existing IP
  ###########################################
  old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
  # Compare if they're the same
  if [[ $ip == $old_ip ]]; then
    logger "DDNS Updater: IP ($ip) for ${record_name} has not changed."
    continue
  fi
  logger "DDNS Update: RECORD HAS CHANGED for ${record_name} from $old_ip to $ip"
  ###########################################
  ## Set the record identifier from result
  ###########################################
  record_identifier=$(echo "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')
  ###########################################
  ## Change the IP@Cloudflare using the API
  ###########################################
  update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header $auth_key" \
                      -H "Content-Type: application/json" \
                      --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxy}")

  ###########################################
  ## Report the status
  ###########################################
  case "$update" in
  *"\"success\":false"*)
    echo -e "DDNS Updater: $ip $record_name DDNS failed for $record_identifier ($ip). DUMPING RESULTS:\n$update" | logger -s
    if [[ $slackuri != "" ]]; then
      curl -L -X POST $slackuri \
      --data-raw '{
        "channel": "'$slackchannel'",
        "text" : "'"$sitename"' DDNS Update Failed: '$record_name': '$record_identifier' ('$ip')."
      }'
    fi
    if [[ $discorduri != "" ]]; then
      curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
      --data-raw '{
        "content" : "'"$sitename"' DDNS Update Failed: '$record_name': '$record_identifier' ('$ip')."
      }' $discorduri
    fi
    ;;
  *)
    logger "DDNS Updater: $ip $record_name DDNS updated."
    if [[ $slackuri != "" ]]; then
      curl -L -X POST $slackuri \
      --data-raw '{
        "channel": "'$slackchannel'",
        "text" : "'"$sitename"' Updated: '$record_name''"'"'s'""' new IP Address is '$ip'"
      }'
    fi
    if [[ $discorduri != "" ]]; then
      curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
      --data-raw '{
        "content" : "'"$sitename"' Updated: '$record_name''"'"'s'""' new IP Address is '$ip'"
      }' $discorduri
    fi
    ;;
  esac

done
