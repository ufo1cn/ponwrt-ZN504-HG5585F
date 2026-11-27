#!/bin/sh
#
# detect-openai.sh - 判人示例脚本（OpenAI 兼容的视觉接口）
#
# 约定：$1 = 快照 JPEG 路径
# 返回：0 = 有人，1 = 无人，3 = 接口异常（camwatch 会按"有人"处理，宁多录不漏录）
#
# 配置来自 /etc/config/camwatch 的 api_url / api_key / model / prompt，
# 也可用同名环境变量覆盖：CW_API_URL / CW_API_KEY / CW_MODEL / CW_PROMPT。

IMG="$1"
[ -f "$IMG" ] || exit 3

API_URL="${CW_API_URL:-$(uci -q get camwatch.main.api_url)}"
API_KEY="${CW_API_KEY:-$(uci -q get camwatch.main.api_key)}"
MODEL="${CW_MODEL:-$(uci -q get camwatch.main.model)}"
PROMPT="${CW_PROMPT:-$(uci -q get camwatch.main.prompt)}"

[ -n "$API_URL" ] || exit 3
[ -n "$API_KEY" ] || exit 3
[ -n "$MODEL" ] || exit 3

B64=$(base64 "$IMG" | tr -d '\r\n')
[ -n "$B64" ] || exit 3

# 请求体写到临时文件，避免命令行长度与转义问题
REQ=/tmp/camwatch.req.json
{
	printf '{"model":"%s","max_tokens":8,"temperature":0,' "$MODEL"
	printf '"messages":[{"role":"user","content":['
	printf '{"type":"text","text":"%s"},' "$PROMPT"
	printf '{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,'
	printf '%s' "$B64"
	printf '"}}]}]}'
} > "$REQ" || exit 3

RESP=/tmp/camwatch.resp.json
curl -sS -m 20 -o "$RESP" \
	-H "Authorization: Bearer $API_KEY" \
	-H 'Content-Type: application/json' \
	--data @"$REQ" "$API_URL" || exit 3

ANS=$(jsonfilter -i "$RESP" -e '@.choices[0].message.content' 2>/dev/null)
[ -n "$ANS" ] || exit 3

# 回答里取第一个数字：>=1 视为有人，0 视为无人；没有数字按异常处理
NUM=$(echo "$ANS" | grep -o '[0-9]' | head -n 1)
case "$NUM" in
	0) exit 1 ;;
	[1-9]) exit 0 ;;
	*) exit 3 ;;
esac
