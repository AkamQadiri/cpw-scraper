#!/bin/bash

#Constants
BASE_PATH="wiseflow"
#Settings
COOKIES_FILE="cookies/wiseflow.txt"
ASSIGNMENT_FOLDER="assignment"
SUBMISSION_FOLDER="submission"
EXPLANATION_FILE="grade_justification.html"
IS="--"
IFS=$'\n'
#Curl
MAIN_URL="https://europe.wiseflow.net/participant/"
FLOWS_URL="https://europe.wiseflow.net/controller/flow/getFlowsInfo.php"
FLOW_URL="https://europe.wiseflow.net/participant/display.php?id="
FLOW_API_URL="https://europe.wiseflow.net/r/api/participant/flow/"
FLOW_EXPLANATION_URL="https://europe.wiseflow.net/r/api/participant/explanation/request/flow/"
#Text
FILE_EXISTS_TEXT="File exists, skipping..."
DONE_TEXT="Done!"

main () {
  BASE_PATH=$(sfilename "$BASE_PATH")
  cmkdir "$BASE_PATH"

  CSRF_ID=$(get_CSRF_ID)
  flows
  echo "$IS$DONE_TEXT$IS"
}

get_CSRF_ID () {
  local output=$(curl -s "$MAIN_URL" --cookie "$COOKIES_FILE" | grep -Eo 'csrfId.+?;C' | awk -F '"' '{print $2}')
  echo "$output"
}

get_flows () {
  local output=$(curl -s "$FLOWS_URL" --cookie "$COOKIES_FILE" -d "action=2&iUserType=1&bArchived=$1&csrfId=$CSRF_ID")
  echo "$output"
}

get_flow () {
  local output=$(curl -s "$FLOW_URL$1" --cookie "$COOKIES_FILE")
  echo "$output"
}

get_flow_assignment () {
  local output=$(curl -s -H "X-CSRFToken: $CSRF_ID" "$FLOW_API_URL$1/assignment" --cookie "$COOKIES_FILE")
  echo "$output"
}

get_flow_explanation () {
  local json=$(curl -s -H "X-CSRFToken: $CSRF_ID" "$FLOW_EXPLANATION_URL$1" --cookie "$COOKIES_FILE")
  local output=$(jq -r '.comments[].annotateComment.text' <<< $json)
  echo "$output"
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

flows () {
  local flow_json_parameters="[.aaData[] | {FlowId: .[0], FlowName: .[3]}]"
  local flows=$(get_flows "false" | jq -r "$flow_json_parameters")
  local archived_flows=$(get_flows "true" | jq -r "$flow_json_parameters")
  local all_flows=$((echo "$flows" ; echo "$archived_flows") | jq  -s ".[0] + .[1]")

  for key in $(jq 'keys | .[]' <<< $all_flows); do
    local flow=$(jq -r ".[$key]" <<< $all_flows)
    local flow_id=$(jq -r '.FlowId' <<< $flow)
    local flow_name=$(sfilename "$(jq -r '.FlowName' <<< $flow)")
    local folder_path="$BASE_PATH/$flow_name"
    local explanation_path="$folder_path/$EXPLANATION_FILE"

    echo "$flow_name ($flow_id)"
    cmkdir "$folder_path"

    local flow_assignment=$(get_flow_assignment "$flow_id")
    local flow_submission=$(get_flow "$flow_id" | grep -Eo '"files".+?}]' | sed 's/"files"://')

    if [[ "$flow_assignment" != "[]" && "$flow_assignment" != "" ]]; then
      local flow_assignment_files=$(echo -e "$flow_assignment" | jq -r "[.[0] | {FileName: .assignment.name, FileDownloadLink: .assignment.downloadUrl}]")
      local flow_appendices_files=$(echo -e "$flow_assignment" | jq -r "[.[0].appendices[] | {FileName: .name, FileDownloadLink: .downloadUrl}]")
      local flow_assignment_appendices_files=$((echo "$flow_assignment_files" ; echo "$flow_appendices_files") | jq  -s ".[0] + .[1]")

      download_files "$folder_path" "$ASSIGNMENT_FOLDER" "$flow_assignment_appendices_files"
    fi;

    if [[ "$flow_submission" != "[]" && "$flow_submission" != "" ]]; then
      flow_submission_files=$(echo -e "$flow_submission" | jq -r "[.[] | {FileName: .name, FileDownloadLink: .download}]")
      download_files "$folder_path" "$SUBMISSION_FOLDER" "$flow_submission_files"
    fi;

    if [ -f "$explanation_path" ]; then
      echo "$IS$FILE_EXISTS_TEXT ($explanation_path)"
      continue
    fi

    local flow_explanation=$(get_flow_explanation "$flow_id")

    if [ ! -z "$flow_explanation" ]; then
      echo "$IS$EXPLANATION_FILE"
      echo "$flow_explanation" > "$explanation_path"
    fi;
  done
}

download_files () {
  local folder_path="$1/$2"

  echo "$IS$2"
  cmkdir "$folder_path"

  for key in $(jq 'keys | .[]' <<< $3); do
    local file=$(jq -r ".[$key]" <<< $3)
    local file_name=$(sfilename "$(jq -r '.FileName' <<< $file)")
    local file_download_link=$(jq -r '.FileDownloadLink' <<< $file)
    local file_path="$folder_path/$file_name"

    if [ -f "$file_path" ]; then
      echo "$IS$IS$FILE_EXISTS_TEXT ($file_path)"
      continue
    fi

    echo "$IS$IS$file_name"
    curl -s "$file_download_link" --cookie "$COOKIES_FILE" --output "$file_path"
  done
}

main "$@"; exit