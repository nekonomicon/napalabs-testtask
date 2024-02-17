#!/bin/sh

URL="$1"

if [ ! "$URL" ]; then
	echo "Provide valid url!"
	echo "Usage:"
	echo "	$0 <URL> [PASSWORD]"
	exit 0
fi

TEMP_DIR="/tmp"
HOST=`echo "$URL"|sed -e 's|^[^/]*//||' -e 's|/.*$||'`

if [ ! "$HOST" ]; then
	echo "Invalid url!" >&2
	exit 1
fi

IP_ADDR=`dig "$HOST" +short|grep -v '\.$'`

if [ ! "$IP_ADDR" ]; then
	IP_ADDR="$HOST"
fi

FILE=`basename "$URL"`

if [ -f "$TEMP_DIR/$FILE" ]; then
	rm -f "$TEMP_DIR/$FILE"
fi

WGET_OUTPUT="$TEMP_DIR/wget-output.txt"
wget -P "$TEMP_DIR" --spider "$URL" > "$WGET_OUTPUT" 2>&1

tcpdump -q -w "$TEMP_DIR/$FILE.pcap" -n net "$IP_ADDR" > /dev/null 2>&1&
TCPDUMP_PID=$!
wget -q -P "$TEMP_DIR" "$URL" > /dev/null 2>&1
ERROR_CODE=$?
sleep 10
kill -15 $TCPDUMP_PID > /dev/null 2>&1

if [ $ERROR_CODE != 0 ]; then
	echo "Couldn't download file!" >&2
	exit 1
elif [ ! -f "$TEMP_DIR/$FILE" ]; then
	echo "Couldn't find $TEMP_DIR/$FILE!" >&2
	exit 1
elif [ ! -f "$TEMP_DIR/$FILE.pcap" ]; then
	echo "Couldn't find $TEMP_DIR/$FILE.pcap!" >&2
	exit 1
fi

tcpflow -q -r "$TEMP_DIR/$FILE.pcap" -o $TEMP_DIR > /dev/null 2>&1
RESTORED_FILE=`sed -ne '/filename/{s/.*<filename>\(.*\)<\/filename>.*/\1/p;q;}' "$TEMP_DIR/report.xml"`

if [ ! -f "$RESTORED_FILE" ]; then
	echo "Couldn't find $RESTORED_FILE!" >&2
	exit 1
fi

mv $RESTORED_FILE "$TEMP_DIR/dump-$FILE" > /dev/null 2>&1

if [ ! -f "$TEMP_DIR/dump-$FILE" ]; then
	echo "Couldn't find $TEMP_DIR/dump-$FILE!" >&2
	exit 1
fi

SIZE1=`grep SIZE "$WGET_OUTPUT"|awk '{print $5}'`
SIZE2=`wc -c < "$TEMP_DIR/$FILE"`

if [ "$SIZE1" ]; then
	if [ $SIZE1 -ne $SIZE2 ]; then
		echo "Downloaded file $TEMP_DIR/$FILE is corrupted!" >&2
		exit 1
	fi
else
	SIZE1=$SIZE2
fi

SIZE2=`wc -c < "$TEMP_DIR/dump-$FILE"`

if [ $SIZE1 -gt $SIZE2 ]; then
	echo "$TEMP_DIR/$dump-FILE less than $TEMP_DIR/$FILE!" >&2
	echo "Restored file $TEMP_DIR/$dump-FILE is corrupted!" >&2
	exit 1
elif [ $SIZE1 -lt $SIZE2 ]; then
	truncate -r "$TEMP_DIR/$FILE" "$TEMP_DIR/dump-$FILE"  > /dev/null 2>&1
fi

CHECKSUM1=`sha512sum $TEMP_DIR/$FILE|awk '{print $1}'`
CHECKSUM2=`sha512sum $TEMP_DIR/dump-$FILE|awk '{print $1}'`

if [ "$CHECKSUM1" != "$CHECKSUM2" ]; then
	echo "Checksums for files $TEMP_DIR/$FILE and $TEMP_DIR/dump-$FILE is not identical!" >&2
	echo "Restored file $TEMP_DIR/dump-$FILE may be corrupted!" >&2
fi

PASSWORD="$2"

if [ "$PASSWORD" ]; then
	unzip -qq -P "$PASSWORD" -t "$TEMP_DIR/dump-$FILE" > /dev/null 2>&1
else
	unzip -qq -t "$TEMP_DIR/dump-$FILE" > /dev/null 2>&1
fi

ERROR_CODE=$?

if [ $ERROR_CODE != 0 ]; then
	echo "Restored file $TEMP_DIR/dump-$FILE is corrupted!" >&2
	exit 1
fi

echo "Done."
