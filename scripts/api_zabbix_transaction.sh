#!/bin/bash

# Variables
# TELEGRAM_BOT_TOKEN="6335231099:AAE2NNjoLk6Sr4yaJxojiN9s6HyetROl6dE"
# TELEGRAM_CHAT_ID="-4155615644" 

transaction_services=$(curl --location 'https://kibana.viettelpost.vn/api/alerting/rules/_find?page=1&per_page=1000&default_search_operator=AND&sort_field=name&sort_order=asc' \
--header 'Authorization: Basic a2liYW5hOkNudHRAMTIz' \
--header 'Cookie: SERVERID=A'\
--silent | jq -r '.data[] | select(.rule_type_id == "apm.transaction_error_rate") | .params.serviceName')

# Call API

for service in $transaction_services
do
	response=$(curl --location 'https://kibana.viettelpost.vn/api/alerting/rules/_find?page=1&per_page=1000&default_search_operator=AND&sort_field=name&sort_order=asc' \
	--header 'Authorization: Basic a2liYW5hOkNudHRAMTIz' \
	--header 'Cookie: SERVERID=A'\
	--silent | jq -r '.data[] | select(.params.serviceName == "'"${service}"'" and .rule_type_id == "apm.transaction_error_rate") | .execution_status.status')

	if [[ $? -ne 0 ]]; then
		echo "API khong hoat dong"
	else
		echo "Status cua dich vu $service: $response"
	fi
done

