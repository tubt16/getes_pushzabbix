#!/bin/bash

# Variables
ELASTICSEARCH_URL="http://localhost:9200"
INDEX=".alert"
tag=$1
VALUE_FILE="/es_zabbix/status_latency_value.txt.$tag" # Save status_latency_value to file

# Read status value from file if exist
if [ -f "$VALUE_FILE" ]; then
  status_latency_value=$(cat "$VALUE_FILE")
else
  status_latency_value="true"
  echo "$status_latency_value" > "$VALUE_FILE"
fi

# Query ES
response=$(curl -s -XGET "$ELASTICSEARCH_URL/$INDEX/_search" -H 'Content-Type: application/json' -d '{
  "query": {
     "range": {
      "timestamp": {
         "gte": "now-5m",
         "lt": "now"
      }
    }
  },
  "sort": [
    {
      "timestamp": {
        "order": "asc"
      }
    }
  ],
  "size": 500
}')

# Get status from ES
while IFS= read -r line; do
    status=$(echo "$line" | jq -r '._source.status')
    contextMessage=$(echo "$line" | jq -r '._source.context_message')

    status_latency=$(echo "$line" | jq -r --arg tag "$tag" '. | select(._source.rule_type == "apm.transaction_duration" and ._source.tag == $tag) | ._source.status')
    contextMessage_latency=$(echo "$line" | jq -r --arg tag "$tag" '. | select(._source.rule_type == "apm.transaction_duration" and ._source.tag == $tag) | ._source.context_message')
    
    if [ "$status_latency" == "false" ]; then
        status_latency_value="false"
    elif [ "$status_latency" == "true" ]; then
        status_latency_value="true"
    fi

    # echo "$status_latency_value" > "$VALUE_FILE"

    # echo "$status_latency_value"
    # echo "$contextMessage_latency"
    # echo "------------------------------------"
done < <(echo "$response" | jq -c --arg tag "$tag" '.hits.hits[] | select(._source.tag == $tag and ._source.rule_type == "apm.transaction_duration")')
 
# echo "####"
# echo "$status_latency_value"

echo "$status_latency_value" > "$VALUE_FILE"

if [ "$status_latency_value" == "true" ]; then
  echo 0
else
  echo 1
fi
