# Cách 1: Query ES & Push Zabbix

**Bước 1: Login vào server cài ES, tạo folder `/es_zabbix`, script thực hiện query ES**

Chúng ta sẽ cần 2 file kịch bản `transaction_final.sh` và `latency_final.sh`

```sh
mkdir /es_monitor

touch /es_monitor/transaction_final.sh
touch /es_monitor/latency_final.sh
```

**Bước 2: Thêm nội dung sau vào 2 file `transaction_final.sh` và `latency_final.sh`**

Nội dung của file `transaction_final.sh`

```sh
#!/bin/bash

# Variables
ELASTICSEARCH_URL="http://localhost:9200"
INDEX=".alert"
tag=$1
VALUE_FILE="/es_zabbix/status_transaction_value.txt.$tag" # Save status_transaction_value to file

# Read status transaction value from file if exist
if [ -f "$VALUE_FILE" ]; then
  status_transaction_value=$(cat "$VALUE_FILE")
else
  status_transaction_value="true"
  echo "$status_transaction_value" > "$VALUE_FILE"
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

    status_transaction=$(echo "$line" | jq -r --arg tag "$tag" '. | select(._source.rule_type == "apm.transaction_error_rate" and ._source.tag == $tag) | ._source.status')
    contextMessage_transaction=$(echo "$line" | jq -r --arg tag "$tag" '. | select(._source.rule_type == "apm.transaction_error_rate" and ._source.tag == $tag) | ._source.context_message')

    if [ "$status_transaction" == "false" ]; then
        status_transaction_value="false"
    elif [ "$status_transaction" == "true" ]; then
        status_transaction_value="true"
    fi

    # echo "$status_transaction_value" > "$VALUE_FILE"

    # echo "$status_transaction_value"
    # echo "$contextMessage_transaction"
    # echo "------------------------------------"
done < <(echo "$response" | jq -c --arg tag "$tag" '.hits.hits[] | select(._source.tag == $tag and ._source.rule_type == "apm.transaction_error_rate")')

# echo "####"
# echo "$status_transaction_value"

echo "$status_transaction_value" > "$VALUE_FILE"

if [ "$status_transaction_value" == "true" ]; then
  echo 0
else
  echo 1
fi
```

Nội dung của file `latency_final.sh`

```sh
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
```

Script `transaction_final.sh` sẽ query ES theo Timestamp của Service và lấy trạng thái cuối cùng phần Transaction của một Service (tùy chỉnh) mà ta đưa vào

Script `latency_final.sh` sẽ query ES theo Timestamp của Service và lấy trạng thái cuối cùng phần Latency của một Service (tùy chỉnh) mà ta đưa vào

Sau khi lấy được trạng thái cuối cùng, Hai script trên sẽ kiểm tra nếu status là `true` sẽ trả về giá trị `0`, nếu là giá trị khác sẽ trả về `1`. Điều này sẽ hữu ích khi sử dụng Trigger cho Zabbix sau này. Ta sẽ để expression của Trigger bằng `1` thì sẽ hiển thị cảnh báo

**Bước 3: Tạo UserParameter**

Thực hiện tạo các UserParameter như sau

```sh
UserParameter=custom.getTransaction[*],sudo /es_zabbix/transaction_final.sh $1
UserParameter=custom.getLatency[*],sudo /es_zabbix/latency_final.sh $1
```

Sau khi tạo xong UserParameter, ta cần restart zabbix-agent để nhận config và cần phần quyền cho user zabbix có quyền chạy script thông qua sudo mà không cần mật khẩu

Restart zabbix-agent

```sh
systemct restart zabbix-agent
``` 

Phân quyền cho User zabbix trong `visudo`

```sh
zabbix  ALL=(ALL)       NOPASSWD:/es_zabbix/transaction_final.sh
zabbix  ALL=(ALL)       NOPASSWD:/es_zabbix/latency_final.sh
```

**Bước 4: Login Zabbix tạo Template, Item, Trigger**

**Thực hiện tạo Template mới có tên là `VTP-APM-GET` sau đó Add các Macros trên Template với giá trị của Macros là `tag` của từng Service trên Index ElasticSearch**

![](/images/macros.png)

**Tiếp tục thực hiện tạo các Item để lấy được trạng thái của mỗi Services mỗi 60s**

![](/images/item_transaction.png)

![](/images/item_latency.png)

**Sau khi tạo Item, ta cần tạo Trigger để đặt cảnh báo dựa trên các giá trị mà Item thu thập được. Ở đây Item sẽ lấy được giá trị `0` hoặc `1` từ 2 script trên**

Với giá trị `0` tức là trạng thái cuối cùng của Service lấy được từ ElasticSearch đang là `true` (Ứng với Service đã Resolved)

Với giá trị `1` tức là trạng thái cuối cùng của Service lấy được từ ElasticSearch đang là `false` (Ứng với Service đang có giá trị Fail Transaction Rate hoặc Latency cao vượt ngưỡng đã đặt ra trên rule APM)

> Vì thế ta cần để Expression của Trigger bằng `1` để khi Item có giá trị `1` thì sẽ có cảnh báo hiển thị trên Zabbix

![](/images/trigger.png)

**Bước 5: Add Template `VTP-APM-GET` lên host ES**

Sau khi có đầy đủ Macros, Item và Trigger trong Template `VTP-APM-GET`, ta chỉ cần add Template này lên Server ES để Monitor

![](/images/host_es.png)


**Ngoài ra sẽ có thêm 2 script để lấy được giá trị Latency và Transaction khi có cảnh báo . 2 Script này sẽ được dùng sau này**

[trigger_value_latency.sh](/scripts/trigger_value_latency.sh)

[trigger_value_transaction.sh](/scripts/trigger_value_transaction.sh)

# Cách 2: GET API & Push Zabbix

Ưu điểm của cách này là script không cần chạy trên chính server ES hoặc các server có thể kết nối đến ES port 9200, cách này chỉ cần chạy trên server kết nối được đến kibana để GET API và lấy ra trạng thái cuối cùng của service có bị match với rule trên index ES hay không

Dưới đây là 2 đoạn script để GET trạng thái (gồm Transaction và Latency) của ALL service

- Nếu status là `ok` tức là Transaction hoặc Latency chưa match rule -> chưa vượt ngưỡng cảnh báo

- Nếu status là `active` tức là Transaction hoặc Latency đã match với rule đưa ra -> vượt ngưỡng cảnh báo

Có thể custom 2 file script này để push cảnh báo về zabbix như cách 1 (phòng trường hợp cách 1 bị lỗi hoặc không muốn chạy script trên node ES nữa)

`api_zabbix_transaction.sh`

```sh
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
```

`api_zabbix_latency.sh`

```sh
#!/bin/bash

# Variables
# TELEGRAM_BOT_TOKEN="6335231099:AAE2NNjoLk6Sr4yaJxojiN9s6HyetROl6dE"
# TELEGRAM_CHAT_ID="-4155615644" 

latency_services=$(curl --location 'https://kibana.viettelpost.vn/api/alerting/rules/_find?page=1&per_page=1000&default_search_operator=AND&sort_field=name&sort_order=asc' \
--header 'Authorization: Basic a2liYW5hOkNudHRAMTIz' \
--header 'Cookie: SERVERID=A'\
--silent | jq -r '.data[] | select(.rule_type_id == "apm.transaction_duration") | .params.serviceName')

# Call API

for service in $latency_services
do
  response=$(curl --location 'https://kibana.viettelpost.vn/api/alerting/rules/_find?page=1&per_page=1000&default_search_operator=AND&sort_field=name&sort_order=asc' \
  --header 'Authorization: Basic a2liYW5hOkNudHRAMTIz' \
  --header 'Cookie: SERVERID=A'\
  --silent | jq -r '.data[] | select(.params.serviceName == "'"${service}"'" and .rule_type_id == "apm.transaction_duration") | .execution_status.status')

  if [[ $? -ne 0 ]]; then
    echo "API khong hoat dong"
  else
    echo "Status cua dich vu $service: $response"
  fi
done
```

Output của 2 đoạn script trên 

![](/images/api_transaction.png)

![](/images/api_latency.png)

Trong đó status `ok` tức là Transaction hoặc Latency chưa vượt ngưỡng, ngược lại status `active` tức là Transaction và Latency đã match rule và vượt ngưỡng đã đặt ra

Ta có thể custom lại 2 đoạn script này và đặt Trigger dựa vào status trả về. Nếu status `active` thì sẽ có cảnh báo, status `ok` thì cảnh báo sẽ Resolve

