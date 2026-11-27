#!/bin/sh
#
# camwatch - 事件录像
#
#   画面变化 -> (可选)云端判人形 -> 有人则开事件 -> 人走后保持 N 秒 -> 收尾
#
# 设计要点：
#   * 只用 camlive 的 /snapshot.jpg 取一帧做变化检测，不常开第二路解码；
#   * 录像不是从事件才开始，而是常开一个环形录制（-c copy 零转码），
#     事件结束时把环形里的片段拷进事件目录，于是天然带"人出现前"的几秒；
#   * 判人失败（超时/接口错）一律按"有人"处理，宁可多录不可漏录。

UCI_GET() { uci -q get "camwatch.main.$1" 2>/dev/null; }
val() { v=$(UCI_GET "$1"); if [ -n "$v" ]; then echo "$v"; else echo "$2"; fi; }

log() { logger -t camwatch "$*"; echo "camwatch: $*" >&2; }

ENABLED=$(val enabled 1)
SNAP_URL=$(val snapshot_url "http://127.0.0.1:8555/snapshot.jpg")
STATUS_URL=$(val status_url "http://127.0.0.1:8555/status.json")
RTSP_URL=$(val rtsp_url "rtsp://127.0.0.1:8554/")
INTERVAL=$(val interval 1)
THRESHOLD=$(val motion_threshold 60)
HOLD=$(val hold_seconds 25)
MISS_LIMIT=$(val miss_limit 2)
PREBUF=$(val prebuffer_seconds 10)
SEG=$(val segment_seconds 5)
RING=$(val ring_segments 8)
DIR=$(val record_dir "/mnt/usb/cam")
MAX_DAYS=$(val max_days 7)
MAX_MB=$(val max_mb 8192)
DETECT_CMD=$(val detect_cmd "")
DETECT_TIMEOUT=$(val detect_timeout 8)

FF=$(command -v ffmpeg)
CURL=$(command -v curl)

SNAP=/tmp/camwatch.snap.jpg
RAW_CUR=/tmp/camwatch.cur
RAW_PRV=/tmp/camwatch.prev
OD_A=/tmp/camwatch.a
OD_B=/tmp/camwatch.b

[ "$ENABLED" = "1" ] || { log "enabled=0，不启动"; exit 0; }
[ -n "$CURL" ] || { log "缺 curl，无法取快照"; exit 1; }
[ -n "$FF" ] || log "缺 ffmpeg：无法取帧做变化检测，也无法录制"

# 环形录制至少要覆盖 预录 + 保持 + 两片余量
need_seg=$(( (PREBUF + HOLD) / SEG + 2 ))
if [ "$need_seg" -gt "$RING" ]; then
	log "ring_segments=$RING 太小，按 预录+保持 调到 $need_seg"
	RING=$need_seg
fi

mkdir -p "$DIR/ring" "$DIR/events" || { log "无法创建 $DIR"; exit 1; }

RING_PID=0
STATE=0			# 0=待机 1=事件录制中
LAST_PRESENT=0		# 最后一次确认有人的时间戳
MISS=0			# 连续"无人"次数

start_ring() {
	[ -n "$FF" ] || return 1
	# 音视频取流：视频恒取第一条（-map 0:v:0），避免多路视频时默认挑到子码流；
	# 音频按 record_audio：1=有麦克风就一起录（-map 0:a:0? 的 ? 表示无音轨不报错），
	# 0=只录视频（-an，省空间，也规避个别机型音轨时间戳错乱）。
	RA=$(val record_audio 1)
	if [ "$RA" = "0" ]; then
		AMAP="-map 0:v:0 -an"
		AMODE="仅视频"
	else
		AMAP="-map 0:v:0 -map 0:a:0?"
		AMODE="视频+音频（有音轨才带）"
	fi
	# -c copy：帧原样封装，不转码，几乎不吃 CPU
	"$FF" -nostdin -loglevel error -rtsp_transport tcp -i "$RTSP_URL" \
		$AMAP -c copy -f segment -segment_time "$SEG" -segment_wrap "$RING" \
		-reset_timestamps 1 "$DIR/ring/seg_%03d.mkv" &
	RING_PID=$!
	log "环形录制已启动 pid=$RING_PID 片长=${SEG}s 片数=$RING 模式=$AMODE"
}

stop_ring() {
	[ "$RING_PID" -gt 0 ] || return 0
	kill "$RING_PID" 2>/dev/null
	wait "$RING_PID" 2>/dev/null
	RING_PID=0
}

# 平均绝对差（千分比，0..1000），越小越静止
frame_score() {
	"$FF" -nostdin -loglevel quiet -y -i "$1" \
		-vf scale=32:24,format=gray -f rawvideo -pix_fmt gray "$RAW_CUR" 2>/dev/null || return 3
	if [ ! -f "$RAW_PRV" ]; then
		cp "$RAW_CUR" "$RAW_PRV"
		echo 0
		return 0
	fi
	od -An -v -tu1 -w768 "$RAW_PRV" > "$OD_A" 2>/dev/null
	od -An -v -tu1 -w768 "$RAW_CUR" > "$OD_B" 2>/dev/null
	awk 'NR==1{for(i=1;i<=NF;i++)a[i]=$i}
	     NR==2{for(i=1;i<=NF;i++){d=$i-a[i];if(d<0)d=-d;s+=d;n++}}
	     END{if(n<1)n=1; printf "%d", s*1000/n/255}' "$OD_A" "$OD_B"
	cp "$RAW_CUR" "$RAW_PRV"
}

# 0=有人 1=无人 2=未配置 3=接口异常
detect_person() {
	if [ -z "$DETECT_CMD" ]; then
		echo 2
		return 0
	fi
	timeout "$DETECT_TIMEOUT" sh -c "$DETECT_CMD" "$1" >/dev/null 2>&1
	rc=$?
	case "$rc" in
		0|1) echo "$rc" ;;
		*) echo 3 ;;
	esac
}

# 把环形里的片段收进事件目录（跳过正在写的那一片）
finalize_event() {
	ts=$(date +%Y%m%d-%H%M%S)
	edir="$DIR/events/$ts"
	mkdir -p "$edir"
	now=$(date +%s)
	n=0
	for f in "$DIR/ring"/seg_*.mkv; do
		[ -f "$f" ] || continue
		mt=$(stat -c %Y "$f" 2>/dev/null || echo 0)
		[ $((now - mt)) -lt 2 ] && continue
		n=$((n + 1))
		cp "$f" "$edir/$(printf 'e_%03d.mkv' "$n")" 2>/dev/null
	done
	{
		echo "start=$EVENT_START"
		echo "end=$now"
		echo "segments=$n"
	} > "$edir/info.txt"
	log "事件收尾: $edir （$n 片，约 $((n * SEG))s）"
	[ "$n" -gt 0 ] || rmdir "$edir" 2>/dev/null
}

cleanup_events() {
	[ -d "$DIR/events" ] || return 0
	find "$DIR/events" -maxdepth 1 -mindepth 1 -type d -mmin +$((MAX_DAYS * 1440)) \
		-exec rm -rf {} \; 2>/dev/null
	used=$(du -sm "$DIR/events" 2>/dev/null | awk '{print $1}')
	while [ "${used:-0}" -gt "$MAX_MB" ]; do
		oldest=$(ls -1dt "$DIR/events"/*/ 2>/dev/null | tail -n 1)
		[ -n "$oldest" ] || break
		log "容量超限 ${used}MB > ${MAX_MB}MB，删除最旧事件 ${oldest}"
		rm -rf "$oldest"
		used=$(du -sm "$DIR/events" 2>/dev/null | awk '{print $1}')
	done
}

on_term() {
	log "收到退出信号"
	stop_ring
	[ "$STATE" = "1" ] && finalize_event
	exit 0
}
trap on_term INT TERM

log "启动: 快照=$SNAP_URL 间隔=${INTERVAL}s 阈值=${THRESHOLD}‰ 保持=${HOLD}s 目录=$DIR"
start_ring

LOOP=0
while :; do
	sleep "$INTERVAL"

	LOOP=$((LOOP + 1))
	if [ $((LOOP % 120)) -eq 0 ]; then
		cleanup_events
	fi
	# 环形录制看门狗
	if [ -n "$FF" ] && ! kill -0 "$RING_PID" 2>/dev/null; then
		log "环形录制进程已退出，重启"
		start_ring
	fi

	# 抓一帧
	"$CURL" -sS -m 4 -o "$SNAP" "$SNAP_URL" || { log "取快照失败"; continue; }
	[ -s "$SNAP" ] || { log "快照为空"; continue; }

	# 卡流检测：frame_age_ms 连续偏大说明摄像头没在出帧
	age=""
	if "$CURL" -sS -m 3 -o /tmp/camwatch.status.json "$STATUS_URL" 2>/dev/null; then
		age=$(jsonfilter -i /tmp/camwatch.status.json -e '@.frame_age_ms' 2>/dev/null)
	fi
	if [ -n "$age" ] && [ "$age" -gt 3000 ] 2>/dev/null; then
		log "视频流停滞 frame_age_ms=$age"
		continue
	fi

	score=$(frame_score "$SNAP")
	if [ "$score" = "3" ]; then
		# 解码失败（图片坏了/ffmpeg 缺）时不做本地门控，直接判人，宁可多调一次
		log "取帧解码失败，跳过本地门控"
		score=1000
	fi

	if [ "$STATE" = "1" ]; then
		# 录制中：判人结果决定是否续命
		rc=$(detect_person "$SNAP")
		now=$(date +%s)
		case "$rc" in
			0)	LAST_PRESENT=$now; MISS=0 ;;
			1)	MISS=$((MISS + 1)) ;;
			*)	MISS=0 ;;	# 接口异常：fail-open，继续录
		esac
		if [ "$MISS" -ge "$MISS_LIMIT" ] && [ $((now - LAST_PRESENT)) -ge "$HOLD" ]; then
			finalize_event
			STATE=0
			MISS=0
		fi
		continue
	fi

	# 待机：先过本地变化门控，才花一次云端调用
	if [ "$score" -lt "$THRESHOLD" ] 2>/dev/null; then
		continue
	fi
	rc=$(detect_person "$SNAP")
	case "$rc" in
		0)
			STATE=1
			EVENT_START=$(date +%s)
			LAST_PRESENT=$EVENT_START
			MISS=0
			log "变化 ${score}‰ + 判人有 -> 开始事件录像"
			;;
		3)
			log "变化 ${score}‰，但判人接口异常，暂不开录"
			;;
		*)
			;;
	esac
done
