#!/usr/bin/env bash
#
# Download TV series and Movies from Soaper using CLI
#
#/ Usage:
#/   ./soaper-dl.sh [-n <name>] [-p <path>] [-e <num1,num2,num3-num4...>] [-l] [-s] [-d]
#/
#/ Options:
#/   -n <name>               TV series or Movie name
#/   -p <path>               media path, e.g: /tv_XXXXXXXX.html
#/                           ignored when "-n" is enabled
#/   -e <num1,num3-num4...>  optional, episode number to download
#/                           e.g: episode number "3.2" means Season 3 Episode 2
#/                           multiple episode numbers separated by ","
#/                           episode range using "-"
#/   -l                      optional, send video or subtitle link to IDM instead of downloading
#/   -s                      optional, download subtitle only
#/   -d                      enable debug mode
#/   -h | --help             display this help message

set -e
set -u

usage() {
    printf "%b\n" "$(grep '^#/' "$0" | cut -c4-)" && exit 1
}

# Helper function to send links to IDM
send_to_idm() {
    local link="$1"
    print_info "Sending link to IDM: $link"
    IDMan.exe /n /d "$link"
}

# Function: download HLS segments with aria2 concurrently and combine with ffmpeg
download_hls_with_aria2() {
    local m3u8_url="$1"
    local output_file="$2"
    local tmp_dir="$3"
    mkdir -p "$tmp_dir"

    print_info "Downloading HLS playlist from: $m3u8_url"
    "$_CURL" -sS "$m3u8_url" -o "$tmp_dir/playlist.m3u8"
    
    # Extract segment URLs (lines not starting with '#')
    grep -v '^#' "$tmp_dir/playlist.m3u8" > "$tmp_dir/segments.txt"
    
    # Determine base URL from m3u8 (in case segments are relative)
    local base_url
    base_url=$(echo "$m3u8_url" | sed 's|\(.*\/\).*|\1|')
    
    # Prepare file containing full segment URLs for aria2
    > "$tmp_dir/aria2_segments.txt"
    local seg count=0
    while IFS= read -r seg; do
        [[ -z "$seg" ]] && continue
        if [[ "$seg" != http* ]]; then
            seg="${base_url}${seg}"
        fi
        count=$((count+1))
        echo "$seg" >> "$tmp_dir/aria2_segments.txt"
    done < "$tmp_dir/segments.txt"
    
    print_info "Downloading $count segments concurrently with aria2..."
    # Adjust concurrency here if needed, e.g. -j 50 -x 50 -s 50 for 50 concurrent downloads
    aria2c -j 16 -x 16 -s 16 -i "$tmp_dir/aria2_segments.txt" -d "$tmp_dir"
    
    # Rename downloaded files to the expected "segment_XXXXX.ts" naming
    local idx=1
    while IFS= read -r seg; do
         local fname
         fname=$(basename "$seg")
         if [ -f "$tmp_dir/$fname" ]; then
              printf -v newname "segment_%05d.ts" "$idx"
              mv "$tmp_dir/$fname" "$tmp_dir/$newname"
              idx=$((idx+1))
         else
              print_warn "File $fname not found in $tmp_dir"
         fi
    done < "$tmp_dir/segments.txt"
    
    # Create a file list for ffmpeg concat demuxer using ls and sed
    (cd "$tmp_dir" && ls -1v *.ts | sed "s/^/file '/; s/$/'/" > filelist.txt)
    
    print_info "Combining segments with ffmpeg..."
    "$_FFMPEG" -f concat -safe 0 -i "$tmp_dir/filelist.txt" -c copy -v error -y "$output_file"
    
    # Clean up temporary files
    rm -rf "$tmp_dir"
}

set_var() {
    _CURL="$(command -v curl)" || command_not_found "curl"
    _JQ="$(command -v jq)" || command_not_found "jq"
    _PUP="$(command -v pup)" || command_not_found "pup"
    _FZF="$(command -v fzf)" || command_not_found "fzf"
    _FFMPEG="$(command -v ffmpeg)" || command_not_found "ffmpeg"

    _HOST="https://soaper.live"
    _SEARCH_URL="$_HOST/search/keyword/"

    _SCRIPT_PATH=$(dirname "$(realpath "$0")")
    _SEARCH_LIST_FILE="${_SCRIPT_PATH}/search.list"
    _SOURCE_FILE=".source.html"
    _EPISODE_LINK_LIST=".episode.link"
    _EPISODE_TITLE_LIST=".episode.title"
    _MEDIA_HTML=".media.html"
    _SUBTITLE_LANG="${SOAPER_SUBTITLE_LANG:-en}"
}

set_args() {
    expr "$*" : ".*--help" > /dev/null && usage
    while getopts ":hlsdn:p:e:" opt; do
        case $opt in
            n)
                _INPUT_NAME="${OPTARG// /%20}"
                ;;
            p)
                _MEDIA_PATH="$OPTARG"
                ;;
            e)
                _MEDIA_EPISODE="$OPTARG"
                ;;
            l)
                _LIST_LINK_ONLY=true
                ;;
            s)
                _DOWNLOAD_SUBTITLE_ONLY=true
                ;;
            d)
                _DEBUG_MODE=true
                set -x
                ;;
            h)
                usage
                ;;
            \?)
                print_error "Invalid option: -$OPTARG"
                ;;
        esac
    done
}

print_info() {
    printf "%b\n" "\033[32m[INFO]\033[0m $1" >&2
}

print_warn() {
    printf "%b\n" "\033[33m[WARNING]\033[0m $1" >&2
}

print_error() {
    printf "%b\n" "\033[31m[ERROR]\033[0m $1" >&2
    exit 1
}

command_not_found() {
    print_error "$1 command not found!"
}

sed_remove_space() {
    sed -E '/^[[:space:]]*$/d;s/^[[:space:]]+//;s/[[:space:]]+$//'
}

download_media_html() {
    "$_CURL" -sS "${_HOST}${1}" > "$_SCRIPT_PATH/$_MEDIA_NAME/$_MEDIA_HTML"
}

get_media_name() {
    "$_CURL" -sS "${_HOST}${1}" \
        | $_PUP ".panel-body h4 text{}" \
        | head -1 \
        | sed_remove_space
}

search_media_by_name() {
    local d t len l n lb
    d="$("$_CURL" -sS "${_SEARCH_URL}$1")"
    t="$($_PUP ".thumbnail" <<< "$d")"
    len="$(grep -c "class=\"thumbnail" <<< "$t")"
    [[ -z "$len" || "$len" == "0" ]] && print_error "Media not found!"

    true > "$_SEARCH_LIST_FILE"
    for i in $(seq 1 "$len"); do
        n="$($_PUP ".thumbnail:nth-child($i) h5 a:nth-child(1) text{}" <<< "$t" | sed_remove_space)"
        l="$($_PUP ".thumbnail:nth-child($i) h5 a:nth-child(1) attr{href}" <<< "$t" | sed_remove_space)"
        lb="$($_PUP --charset UTF-8 ".thumbnail:nth-child($i) .label-info text{}" <<< "$t" | sed_remove_space)"
        echo "[$l][$lb] $n" | tee -a "$_SEARCH_LIST_FILE"
    done
}

is_movie() {
    [[ "$1" =~ ^/movie_.* ]] && return 0 || return 1
}

download_source() {
    local d a
    mkdir -p "$_SCRIPT_PATH/$_MEDIA_NAME"
    d="$("$_CURL" -sS "${_HOST}${_MEDIA_PATH}")"
    a="$($_PUP ".alert-info-ex" <<< "$d")"
    if is_movie "$_MEDIA_PATH"; then
        download_media "$_MEDIA_PATH" "$_MEDIA_NAME"
    else
        echo "$a" > "$_SCRIPT_PATH/$_MEDIA_NAME/$_SOURCE_FILE"
    fi
}

download_episodes() {
    local origel el uniqel se
    origel=()
    if [[ "$1" == *","* ]]; then
        IFS="," read -ra ADDR <<< "$1"
        for n in "${ADDR[@]}"; do
            origel+=("$n")
        done
    else
        origel+=("$1")
    fi

    el=()
    for i in "${origel[@]}"; do
        if [[ "$i" == *"-"* ]]; then
            se=$(awk -F '-' '{print $1}' <<< "$i" | awk -F '.' '{print $1}')
            s=$(awk -F '-' '{print $1}' <<< "$i" | awk -F '.' '{print $2}')
            e=$(awk -F '-' '{print $2}' <<< "$i" | awk -F '.' '{print $2}')
            for n in $(seq "$s" "$e"); do
                el+=("${se}.${n}")
            done
        else
            el+=("$i")
        fi
    done

    IFS=" " read -ra uniqel <<< "$(printf '%s\n' "${el[@]}" | sort -u -V | tr '\n' ' ')"
    [[ ${#uniqel[@]} == 0 ]] && print_error "Wrong episode number!"

    for e in "${uniqel[@]}"; do
        download_episode "$e"
    done
}

download_episode() {
    local l
    l=$(grep "\[$1\] " "$_SCRIPT_PATH/$_MEDIA_NAME/$_EPISODE_LINK_LIST" \
        | awk -F '] ' '{print $2}')
    [[ "$l" != *"/"* ]] && print_error "Wrong download link or episode not found!"
    download_media "$l" "$1"
}

download_media() {
    local u d el sl p
    download_media_html "$1"
    is_movie "$_MEDIA_PATH" && u="GetMInfoAjax" || u="GetEInfoAjax"
    p="$(sed 's/.*e_//;s/.html//' <<< "$1")"
    d="$("$_CURL" -sS "${_HOST}/home/index/${u}" \
        -H "referer: https://${_HOST}${1}" \
        --data-raw "pass=${p}")"
    el="${_HOST}$($_JQ -r '.val' <<< "$d")"
    [[ "$el" != *".m3u8" ]] && el="$($_JQ -r '.val_bak' <<< "$d")"
    if [[ "$($_JQ '.subs | length' <<< "$d")" -gt "0" ]]; then
        sl="$($_JQ -r '.subs[]| select(.name | ascii_downcase | contains ("'"$_SUBTITLE_LANG"'")) | .path' <<< "$d" | head -1)"
        sl="${sl// /%20}"
        sl="${sl//[/\\\[}"
        sl="${sl//]/\\\]}"
        sl="${_HOST}$sl"
    fi

    if [[ -z ${_LIST_LINK_ONLY:-} ]]; then
        if [[ -n "${sl:-}" && "$sl" != "$_HOST" ]]; then
            print_info "Downloading subtitle $2..."
            "$_CURL" "${sl}" > "$_SCRIPT_PATH/${_MEDIA_NAME}/${2}_${_SUBTITLE_LANG}.srt"
        fi
        if [[ -z ${_DOWNLOAD_SUBTITLE_ONLY:-} ]]; then
            print_info "Downloading video $2 with aria2..."
            download_hls_with_aria2 "$el" "$_SCRIPT_PATH/${_MEDIA_NAME}/${2}.mp4" "$_SCRIPT_PATH/${_MEDIA_NAME}/hls_$2"
        fi
    else
        if [[ -z ${_DOWNLOAD_SUBTITLE_ONLY:-} ]]; then
            send_to_idm "$el"
        else
            if [[ -n "${sl:-}" ]]; then
                send_to_idm "$sl"
            fi
        fi
    fi
}

create_episode_list() {
    local slen sf t l sn et el
    sf="$_SCRIPT_PATH/$_MEDIA_NAME/$_SOURCE_FILE"
    el="$_SCRIPT_PATH/$_MEDIA_NAME/$_EPISODE_LINK_LIST"
    et="$_SCRIPT_PATH/$_MEDIA_NAME/$_EPISODE_TITLE_LIST"
    slen="$(grep 'alert alert-info-ex' -c "$sf")"
    true > "$et"
    true > "$el"
    for i in $(seq "$slen" -1 1); do
        sn=$((slen - i + 1))
        t="$($_PUP ".alert-info-ex:nth-child($i) div text{}" < "$sf" \
            | sed_remove_space \
            | tac \
            | awk '{print "[" num  "." NR "] " $0}' num="${sn}")"
        l="$($_PUP ".alert-info-ex:nth-child($i) div a attr{href}" < "$sf" \
            | sed_remove_space \
            | tac \
            | awk '{print "[" num  "." NR "] " $0}' num="${sn}")"
        echo "$t" >> "$et"
        echo "$l" >> "$el"
    done
}

select_episodes_to_download() {
    cat "$_SCRIPT_PATH/$_MEDIA_NAME/$_EPISODE_TITLE_LIST" >&2
    echo -n "Which episode(s) to download: " >&2
    read -r s
    echo "$s"
}

main() {
    set_args "$@"
    set_var

    local mlist=""
    if [[ -n "${_INPUT_NAME:-}" ]]; then
        mlist="$(search_media_by_name "$_INPUT_NAME")"
        _MEDIA_PATH=$($_FZF -1 <<< "$(sort -u <<< "$mlist")" | awk -F']' '{print $1}' | sed -E 's/^\[//')
    fi

    [[ -z "${_MEDIA_PATH:-}" ]] && print_error "Media not found! Missing option -n <name> or -p <path>?"
    [[ ! -s "$_SEARCH_LIST_FILE" ]] && print_error "$_SEARCH_LIST_FILE not found. Please run \`-n <name>\` to generate it."
    _MEDIA_NAME=$(sort -u "$_SEARCH_LIST_FILE" \
                | grep "$_MEDIA_PATH" \
                | awk -F '] ' '{print $2}' \
                | sed -E 's/\//_/g')
    [[ "$_MEDIA_NAME" == "" ]] && _MEDIA_NAME="$(get_media_name "$_MEDIA_PATH")"

    download_source

    is_movie "$_MEDIA_PATH" && exit 0

    create_episode_list

    [[ -z "${_MEDIA_EPISODE:-}" ]] && _MEDIA_EPISODE=$(select_episodes_to_download)
    download_episodes "$_MEDIA_EPISODE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
