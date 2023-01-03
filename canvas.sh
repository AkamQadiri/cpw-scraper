#!/bin/bash

#Constants
BASE_PATH="canvas"
#Settings
COOKIES_FILE="cookies/canvas.txt"
ASSIGNMENT_TEXT_FILENAME="assignment.html"
COMMENTS_FILENAME="comments.txt"
IS="--"
IFS=$'\n'
#Curl
BASE_URL="https://kristiania.instructure.com"
ACCEPT_HEADER="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
#Text
SKIPPING_CONTEXT_MODULE_TEXT="Context Module Sub Header, skipping..."
FILE_EXISTS_TEXT="File exists, skipping..."
DONE_TEXT="Done!"

main () {
  BASE_PATH=$(sfilename "$BASE_PATH")
  cmkdir "$BASE_PATH"

  courses
  echo "$IS$DONE_TEXT$IS"
}

get_internal_page () {
  local output=$(curl -s -L -H "$ACCEPT_HEADER" "$BASE_URL$1" --cookie "$COOKIES_FILE")
  echo "$output"
}

download () {
  curl -s -L "$2" --cookie "$COOKIES_FILE" --output "$1"
}

xpath () {
  local output=$(xmllint --html --xpath "$1" 2>/dev/null -)
  echo "$output"
}

xml_decode () {
  local output=$(echo "$1" | sed -e 's/&nbsp;/ /g; s/&amp;/\&/g; s/&#9;//g; s/&lt;/\</g; s/&gt;/\>/g; s/&quot;/\"/g; s/#&#39;/\'"'"'/g; s/&ldquo;/\"/g; s/&rdquo;/\"/g;')
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

courses () {
  local courses_page=$(get_internal_page "/courses/" | grep  'href="/courses/')
  local courses=($(echo "$courses_page" | awk -F '"' '{print $2"\n"}'))
  local course_titles=($(echo "$courses_page" | awk -F '"' '{printf $4"\n"}'))

  for course_index in ${!courses[@]}; do
    local course_title=$(sfilename "${course_titles[$course_index]}")
    local course_url="${courses[$course_index]}"
    local course_page=$(get_internal_page "$course_url")
    local course_file_path="$BASE_PATH/$course_title"

    echo "$course_title - $course_url"
    cmkdir "$course_file_path"

    course_modules "$course_file_path" "$course_page"
  done
}

course_modules () {
  local page=$(echo "$2" | xpath "//*[contains(@class, 'context_module_option')]")
  local modules=($(echo "$page" | awk -F '"' '{print $2"\n"}'))
  local module_titles=($(echo "$page" | awk -F '[<>]' '{print $3"\n"}'))

  for course_module_index in ${!modules[@]}; do
    local module_title=$(sfilename "${module_titles[$course_module_index]}")
    local module_id=${modules[$course_module_index]}
    local module_file_path="$1/$module_title"

    echo "$IS$module_title ($module_id)"
    cmkdir "$module_file_path"

    course_module_items "$module_file_path" "$2" "$module_id"
  done
}

course_module_items () {
  local module_items=($(echo "$2" | xpath "//*[@id='context_module_content_$3']/ul/li/@id" | awk -F '"' '{print $2"\n"}'))

  for module_item in ${module_items[@]}; do
    local module_item_type=$(echo "$2" | xpath "//*[@id='$module_item']//*[contains(@class, 'type_icon')]/@title" | awk -F '"' '{print $2}' | sed 's/.*/\U&/g')

    if [[ "$module_item_type" = "KONTEKST MODUL SUB-HEADER" || "$module_item_type" = "CONTEXT MODULE SUB HEADER" || "$module_item_type" = "CONTEXT MODULE SUBHEADER" ]]; then
      echo "$IS$IS$SKIPPING_CONTEXT_MODULE_TEXT"
      continue
    fi

    local module_item_html=$(xml_decode "$(echo "$2" | xpath "//*[@id='$module_item']//*[contains(@class, 'item_name')]/a")")
    local module_item_name_trimmed=$(trim "$(echo "$module_item_html" | awk -F '"' '{print $2}')")

    if [[ "$module_item_html" = *"data-item-href"* ]]; then
      local module_item_link=$(echo "$module_item_html" | awk -F '"' '{print $10}')
    else
      local module_item_link=$(echo "$module_item_html" | awk -F '"' '{print $6}')
    fi

    item "$1" "$module_item_link" "$module_item_type" "$module_item_name_trimmed"
  done
}

item () {
  local item_page=$(get_internal_page "$2")
  local item_main_link=$(xml_decode "$(echo "$item_page" | xpath "(//*[contains(@class, 'ic-Layout-contentMain')]//a)[1]/@href" | awk -F '"' '{print $2}')")
  local module_item_name=$(sfilename "$4")
  local module_item_file_path="$1/$module_item_name"

  case "$3" in
    "VEDLEGG" | "ATTACHMENT")
      local file_name=$(sfilename "$(echo "$item_page" | xpath "//*[contains(@class, 'ic-Layout-contentMain')]/h2/text()")")
      local file_path="$1/$file_name"

      if [[ -f "$file_path" ]]; then
        echo "$IS$IS$FILE_EXISTS_TEXT ($file_path)"
        return
      fi
      
      echo "$IS$IS$file_name ($3) - $2"
      download "$file_path" "$BASE_URL$item_main_link"
      ;;

    "OPPGAVE" | "ASSIGNMENT")
      echo "$IS$IS$module_item_name ($3) - $2"
      local assignment_text=$(echo "$item_page" | xpath "//*[@id='assignment_show']")
      local submission_html=$(echo "$item_page" | xpath "(//*[@id='sidebar_content']//*[contains(@class, 'content')]//a)[2]")
      local comments_html=$(echo "$item_page" | xpath "//*[contains(@class, 'comments module')]/div")

      local submission_name=$(sfilename "$(echo "$submission_html" | grep -Eo 'Last ned.*' | cut -d' ' -f3-)")
      local submission_link=$(echo "$submission_html" | awk -F '"' '{print $2}')
      local submission_link="$BASE_URL$submission_link"

      local comments=($(echo "$comments_html" | grep -Eo 'id="comment-.*' | awk -F '"' '{print $2"\n"}'))

      local assignment_text_file_path="$module_item_file_path/$ASSIGNMENT_TEXT_FILENAME"
      local submission_file_path="$module_item_file_path/$submission_name"
      local comments_file_path="$module_item_file_path/$COMMENTS_FILENAME"

      cmkdir "$module_item_file_path"

      if [[ ! -f "$assignment_text_file_path" ]]; then
        echo "$IS$IS$IS$ASSIGNMENT_TEXT_FILENAME ($3) - $2"
        echo "$assignment_text" | cat -s > "$assignment_text_file_path"
      else
        echo "$IS$IS$IS$FILE_EXISTS_TEXT ($assignment_text_file_path)"
      fi

      if [[ ! -f "$submission_file_path" ]]; then
        echo "$IS$IS$IS$submission_name ($3) - $2"

        download "$submission_file_path" "$submission_link"
      else
        echo "$IS$IS$IS$FILE_EXISTS_TEXT ($submission_file_path)"
      fi

      if [[ ! -f "$comments_file_path" ]]; then
        echo "$IS$IS$IS$COMMENTS_FILENAME ($3) - $2"
        local attachment_count=$((0))

        for comment_id in ${comments[@]}; do
          local comment=$(trim "$(echo "$item_page" | xpath "(//*[@id='$comment_id']/text())[1]" | tr -d '\n')")
          local attachment_html=$(echo "$item_page" | xpath "//*[@id='$comment_id']//*[contains(@class, 'comment_attachment_link')]")
          local signature=$(trim "$(echo "$item_page" | xpath "//*[@id='$comment_id']/*[contains(@class, 'signature')]/text()" | tr -d '\n')")
          local formatted_comment="$comment - $signature"

          if [ ! -z "$attachment_html" ]; then
            attachment_count=$(($attachment_count + 1))
            local attachment_link=$(echo "$attachment_html" | awk -F '"' '{print $2}')
            local attachment_name=$(sfilename "$(echo "$attachment_html" | awk -F '[><]' '{print $3}')")
            local formatted_comment="$formatted_comment (Attached: $attachment_count)"
            local attachments_path="$module_item_file_path/Attachments"
            local attachment_path="$attachments_path/($attachment_count)_$attachment_name"

            cmkdir "$attachments_path"

            if [[ ! -f "$attachment_path" ]]; then
              echo "$IS$IS$IS$IS($attachment_count)_$attachment_name ($3) - $2"
              download "$attachment_path" "$BASE_URL$attachment_link"
            else
              echo "$IS$IS$IS$IS$FILE_EXISTS_TEXT ($attachment_path)"
            fi
          fi

          echo "$formatted_comment" >> "$comments_file_path"
        done
      else
        echo "$IS$IS$IS$FILE_EXISTS_TEXT ($comments_file_path)"
      fi
      ;;

    "SIDE" | "PAGE")
      local page_content=$(echo "$item_page" | grep -Eo '"body":"(.*)"},' | sed 's/"body":"//; s/"},//; s/\\"/"/g;')
      page_content=$(xml_decode "$(echo -e "$page_content")")

      local downloadable_files=$(echo "$page_content" | xpath "//a[contains(@class, 'instructure_file_link')]")
      local iframe_src=$(echo "$page_content" | xpath "//iframe/@src" | awk -F '"' '{print $2}')
      local file_path="$module_item_file_path"
      local print_indents="$IS$IS"

      if [ -z "$downloadable_files" ]; then
        file_path="$file_path.html"
      else
        echo "$IS$IS$module_item_name ($3) - $2"
        cmkdir "$file_path"
        file_path="$file_path/$module_item_name.html"
        print_indents="$IS$IS$IS"
      fi
      
      for d_file in ${downloadable_files[@]}; do
        local d_file_name=$(sfilename "$(echo "$d_file" | xpath "//a[contains(@class, 'instructure_file_link')]/@title" | awk -F '"' '{print $2}')")

        if [ -z "$d_file_name" ]; then
          d_file_name=$(sfilename "$(echo "$d_file" | xpath "//a[contains(@class, 'instructure_file_link')]/text()")")
        fi

        local d_file_url=$(echo "$d_file" | xpath "//a[contains(@class, 'instructure_file_link')]/@href" | awk -F '"' '{print $2}' | sed -e 's/?wrap.*/\/download/')
        local d_file_path="$module_item_file_path/$d_file_name"

        if [[ -f "$d_file_path" ]]; then
          echo "$IS$IS$IS$FILE_EXISTS_TEXT ($d_file_path)"
          continue
        fi

        echo "$IS$IS$IS$d_file_name ($3) - $d_file_url"
        download "$d_file_path" "$d_file_url"
      done

      if [[ -f "$file_path" ]]; then
        echo "$print_indents$FILE_EXISTS_TEXT ($file_path)"
        return
      fi

      echo "$print_indents$module_item_name ($3) - $2"

      if [ ! -z "$iframe_src" ]; then
        download "$file_path" "$iframe_src"
        return
      fi

      echo -e "$page_content" > "$file_path"
      ;;

    "EKSTERN URL" | "EXTERNAL URL")
      local file_path="$module_item_file_path.desktop"

      if [[ -f "$file_path" ]]; then
        echo "$IS$IS$FILE_EXISTS_TEXT ($file_path)"
        return
      fi

      echo "$IS$IS$module_item_name ($3) - $2"
      echo -e "[Desktop Entry]\nEncoding=UTF-8\nName=$4\nType=Link\nURL=$item_main_link\nIcon=text-html" > "$file_path"
      ;;

    "EKSTERNT VERKTØY" | "DISKUSJONSTEMA" | "EXTERNAL TOOL" | "DISCUSSION TOPIC" | "QUIZ")
      echo "$IS$IS""Skipping ($3) - $2"
      ;;

    *)
      echo "$IS$ISUnknown type found ($3)"
      exit
      ;;
  esac
}

main "$@"; exit