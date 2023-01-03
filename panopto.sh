#!/bin/bash

#Constants
BASE_PATH="panopto"
#Settings
COOKIES_FILE="cookies/panopto.txt"
FOLDER_DATA_URL="https://kristiania.cloud.panopto.eu/Panopto/Services/Data.svc/GetFolderInfo"
SESSION_DATA_URL="https://kristiania.cloud.panopto.eu/Panopto/Services/Data.svc/GetSessions"
DELIVERY_INFO_URL="https://kristiania.cloud.panopto.eu/Panopto/Pages/Viewer/DeliveryInfo.aspx"
FOLDER_IDS=()
IS="--"
#Text
FILE_EXISTS_TEXT="File exists, skipping..."
ERROR_ACCESSING_FOLDER_TEXT="Error accessing folder"
SKIPPING_FOLDER_TEXT="Skipping folder..."
NO_WORKING_VIDEO_URL_TEXT="Couldn't find any working video url!"
EXITING_TEXT="Exiting program!"
MULTIPLE_STREAMS_FOUND="Multiple Streams found, please investigate."
DONE_TEXT="Done!"

main () {
  BASE_PATH=$(sfilename "$BASE_PATH")
  cmkdir "$BASE_PATH"

  panopto
  echo "$IS$DONE_TEXT$IS"
}

trim () {
  local output=$(echo "$1" | sed -e 's/^[[:space:]]*//; s/[[:space:]]*$//')
  echo "$output"
}

sfilename () {
  local output=$(trim "$1" | sed -z 's/\n/_/; s/+/p/g; s/[^A-Za-zæøåÆØÅ0-9._-]/_/g; s/^_*//g; s/_*$//g; s/_\+/_/g')
  echo "$output"
}

cmkdir () {
  mkdir "$1" 2>/dev/null
}

get_folder_data () {
  local post_data='{"folderID":"'$1'"}'
  local output=$(curl -s -H "Content-Type: application/json; charset=utf-8" --data-raw "$post_data" "$FOLDER_DATA_URL" --cookie "$COOKIES_FILE")
  echo "$output"
}

get_session_data () {
  local post_data='{"queryParameters":{"folderID":"'$1'", "getFolderData": true}}'
  local output=$(curl -s -H "Content-Type: application/json; charset=utf-8" --data-raw "$post_data" "$SESSION_DATA_URL" --cookie "$COOKIES_FILE")
  echo "$output"
}

get_delivery_data () {
  local output=$(curl -s -d "deliveryId=$1&responseType=json" "$DELIVERY_INFO_URL" --cookie "$COOKIES_FILE")
  echo "$output"
}

panopto () {
  for folder_id in ${FOLDER_IDS[@]}; do
    download_folder "$BASE_PATH" "$folder_id" "$((0))"
  done
}

get_indents () {
  if [ "$1" -eq "0" ]; then
    return
  fi

  indent_symbol=$(for i in {1..$1}; do echo -n "$IS"; done)
  echo "$indent_symbol"
}

download_folder () {
  local folder_id="$2"
  local folder_data=$(get_folder_data "$folder_id")
  local session_data=$(get_session_data "$folder_id")
  local folder_name=$(sfilename "$(jq -r '.d.Name //empty' <<< $folder_data 2>/dev/null)")
  local subfolders=($(jq -r '.d.Subfolders[]? | .ID //empty' <<< $session_data 2>/dev/null))
  local folder_path="$1/$folder_name"
  local indents=$(get_indents "$3")

  if [ -z "$folder_name" ]; then
    echo "$indents$ERROR_ACCESSING_FOLDER_TEXT ($folder_id)"
    echo "$indents$SKIPPING_FOLDER_TEXT"
    return;
  fi

  cmkdir "$folder_path"
  echo "$indents$folder_name ($folder_id)"
  download_folder_videos "$folder_path" "$indents" "$folder_id"

  local recursive_count=$(($3 + 1))
  for subfolder_id in ${subfolders[@]}; do
    download_folder "$folder_path" "$subfolder_id" "$recursive_count"
  done
}

download_folder_videos () {
  local folder_path=$1
  local indents="$2$IS"
  local session_data=$(get_session_data "$3")
  local video_list=$(jq -r '[.d.Results[] | {Name: .SessionName, Url: .IosVideoUrl, DeliveryID: .DeliveryID}]' <<< $session_data)

  for key in $(jq 'keys | .[]' <<< $video_list); do
    local video=$(jq -r ".[$key]" <<< $video_list)
    local video_title=$(sfilename "$(jq -r '.Name' <<< $video)")
    local video_url=$(jq -r '.Url' <<< $video | sed 's/.mp4/.hls\/master.m3u8/')
    local video_path="$folder_path/$video_title.mp4"

    if [ -f "$video_path" ]; then
      echo "$indents$FILE_EXISTS_TEXT ($video_path)"
      continue
    fi

    echo "$indents$video_title"
    yt-dlp -q --progress $video_url -o "$video_path" --cookies "$COOKIES_FILE" 2>/dev/null

    if [ $? -ne 0 ]; then
      local delivery_id=$(jq -r '.DeliveryID' <<< $video)

      download_video_alternative_method "$folder_path" "$video_title" "$delivery_id" "$indents"
    fi
  done
}

download_video_alternative_method () {
  local folder_path=$1
  local indents=$4
  local delivery_info=$(get_delivery_data "$3")
  local streams=$(jq -r '[.Delivery.Streams[]? | {Url: .StreamUrl, Type: .StreamType} | select(.Url != null ) ]' <<< $delivery_info)
  local podcasts=$(jq -r '[.Delivery.PodcastStreams[]? | {Url: .StreamUrl, Type: 3} | select(.Url != null ) ]' <<< $delivery_info)
  local videos=$podcasts
  local path="$folder_path/$2"
  
  local stream_count=$(jq -r 'length' <<< $streams)

  if [ "$stream_count" -gt "1" ]; then
    videos=$((echo "$streams" ; echo "$podcasts") | jq '. + input')
  fi

  if [ "$videos" = "[]" ]; then
    echo "$indents$NO_WORKING_VIDEO_URL_TEXT"
    echo "$indents$EXITING_TEXT$IS"
    exit
  fi

  local video_count=$(jq -r 'length' <<< $videos)

  if [ "$video_count" -gt "1" ]; then
    local camera_count=$((1))
    local screen_count=$((1))
    
    cmkdir "$path"
    for key in $(jq 'keys | .[]' <<< $videos); do
      local video=$(jq -r ".[$key]" <<< $videos)
      local video_url=$(jq -r '.Url' <<< $video)
      local video_type=$(jq -r '.Type' <<< $video)
      local video_path="$path"
      local video_name=""

      case "$video_type" in
        "1")
            video_name="camera"
            
            if [ "$camera_count" -gt "1" ]; then
              video_name="camera_$camera_count"
            fi

            video_path="$video_path/$video_name.mp4"
            camera_count=$(($camera_count + 1))
          ;;
        "2")
            video_name="screen"
            
            if [ "$screen_count" -gt "1" ]; then
              video_name="screen_$screen_count"
            fi

            video_path="$video_path/$video_name.mp4"
            screen_count=$(($screen_count + 1))
          ;;
        "3")
            video_name="lecture"
            video_path="$video_path/$video_name.mp4"
          ;;
      esac

      if [ -f "$video_path" ]; then
        echo "$indents$IS$FILE_EXISTS_TEXT ($video_path)"
        continue
      fi
      
      echo "$indents$IS$video_name"
      yt-dlp -q --progress $video_url -o "$video_path" --cookies "$COOKIES_FILE"
    done
  else
    local video_url=$(jq -r '.[].Url' <<< $videos)
    local video_path="$path.mp4"
    yt-dlp -q --progress $video_url -o "$video_path" --cookies "$COOKIES_FILE"
  fi
}

main "$@"; exit