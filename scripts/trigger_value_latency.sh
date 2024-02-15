#!/bin/bash

# Variables
ELASTICSEARCH_URL="http://localhost:9200"
INDEX=".alert"
tag=$1

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
    trigger_value_latency=$(echo "$line" | jq -r --arg tag "$tag" '. | select(._source.rule_type == "apm.transaction_duration" and ._source.tag == $tag) | ._source.trigger_value')
    trigger_threshold_transaction=$(echo "$line" | jq -r --arg tag "$tag" '. | select(._source.rule_type == "apm.transaction_duration" and ._source.tag == $tag) | ._source.trigger_threshold')
    # echo "$trigger_value_latency"

done < <(echo "$response" | jq -c --arg tag "$tag" '.hits.hits[] | select(._source.tag == $tag and ._source.rule_type == "apm.transaction_duration" and ._source.status == false)')

if [[ -n "$trigger_value_latency" ]]; then
  echo "$trigger_value_latency"
fi
