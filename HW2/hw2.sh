#!/bin/sh

ORIG_PWD=$(pwd)
cnt=0

usage() {
    echo 'hw2.sh -i INPUT -o OUTPUT [-c csv|tsv] [-j]' >&2
    printf "\nAvailable Options:\n" >&2
    echo '-i: Input file to be decoded' >&2
    echo '-o: Output directory' >&2
    echo '-c csv|tsv: Output files.[ct]sv' >&2
    echo '-j: Output info.json' >&2
    exit 1
}

mkdir_or_write() {
    head=$(echo "$1" | awk -F'/' '{print $1}')
    tail=$(echo "$1" | sed -E 's#[^\/]+\/##')
    if [ "$head" = "$1" ]; then
        if [ -r "/tmp/_files/$(echo "$2" | base64)" ]; then
            cp "/tmp/_files/$(echo "$2" | base64)" "$head"
        else
            touch "$head"
        fi
    else
        mkdir "$head" 2>/dev/null
        cd "$head" || exit
        mkdir_or_write "$tail" "$2"
    fi
}

gen_info() {
    timestamp=$(yq .date "$INPUT")
    #new_date=$(date -d@"$timestamp" -I'seconds')
    new_date=$(date -Iseconds -j -f "%s" "$timestamp")
    cat "$INPUT" | sed "s/date: $timestamp/date: $new_date/" | \
        yq -o json '{"name": .name, "author": .author, "date": .date}'
}

j=false
c=""
while getopts ":i:o:c:j" args; do
    case "${args}" in
        i)
            INPUT=${OPTARG}
            ;;
        o)
            OUTPUT_DIR=${OPTARG}
            ;;
        c)
            c=${OPTARG}
            [ "$c" = 'tsv' ] || [ "$c" = 'csv' ] || usage
            ;;
        j)
            j=true
            ;;
    esac
done

[ -n "$INPUT" ] && [ -n "$OUTPUT_DIR" ] || usage
RECURSIVE=false
[ $j = 'false' ] && [ -z "$c" ] && RECURSIVE=true

mkdir "$OUTPUT_DIR" 2>/dev/null

if $j; then
    gen_info > "$OUTPUT_DIR/info.json"
fi

FILES_LIST=$(yq '.files | filter(.type =="file") | .[].name' < $INPUT)
HW2_LIST=$(yq '.files | filter(.type =="hw2") | .[].name' < $INPUT)

sudo rm -rf /tmp/_files 2>/dev/null
mkdir /tmp/_files
yq "$INPUT" > /tmp/_tmp.hw2
for f in $FILES_LIST; do
    # read file and get size
    fb64=$(echo "$f" | base64)
    yq ".files | filter(.name == \"$f\") | .[].data" "$INPUT" | base64 -d > "/tmp/_files/$fb64"
    size=$(cat "/tmp/_files/$fb64" | wc -c)

    # prepare for size append
    f2=$(echo "$f" | sed 's#/#\\/#g')
    awkcmd="/"$f2"/ { print; print \"    size: "$size"\"; next }1"
    cat /tmp/_tmp.hw2 | awk "$awkcmd" > "/tmp/__tmp.hw2"
    cp /tmp/__tmp.hw2 /tmp/_tmp.hw2

    if [ "$(md5sum "/tmp/_files/$fb64" | awk '{print $1}')" != "$(yq ".files | filter(.name == \"$f\") | .[].hash.md5" $INPUT)" ]; then
        cnt=$((cnt+1))
        continue
    fi
    if [ "$(sha1sum "/tmp/_files/$fb64" | awk '{print $1}')" != "$(yq ".files | filter(.name == \"$f\") | .[].hash.sha-1" $INPUT)" ]; then
        cnt=$((cnt+1))
        continue
    fi
    mkdir_or_write "$OUTPUT_DIR/$f" "$f"
    cd "$ORIG_PWD" || exit
done

for f in $HW2_LIST; do
    # read file and get size
    fb64=$(echo "$f" | base64)
    yq ".files | filter(.name == \"$f\") | .[].data" "$INPUT" | base64 -d > "/tmp/_files/$fb64"
    size=$(cat "/tmp/_files/$fb64" | wc -c)

    ## prepare for size append
    #f2=$(echo $f | sed 's#/#\\/#g')
    #cat /tmp/_tmp.hw2 | awk '/'$f2'/ { print; print "    size: '$size'"; next }1' > /tmp/__tmp.hw2
    #cp /tmp/__tmp.hw2 /tmp/_tmp.hw2

    mkdir_or_write "$OUTPUT_DIR/$f" "$f"
    cd "$ORIG_PWD" || exit
    if $RECURSIVE; then
        ./hw2.sh -i "$OUTPUT_DIR/$f" -o "$OUTPUT_DIR"
    fi
done

if [ -n "$c" ]; then
    echo 'name,size,md5,sha1' > "$OUTPUT_DIR/files.csv"
    cat /tmp/_tmp.hw2 | yq -ocsv '.files[] | [{"name": .name, "size": .size, "md5": .hash.md5, "sha1": .hash.sha-1}]' | grep -v 'name,size,md5,sha1' >> files.csv
    if [ "$c" = 'tsv' ]; then
        cat files.csv | tr "," "\t" > "$OUTPUT_DIR/files.tsv"
        rm files.csv
    fi
fi

echo $cnt


