#!/bin/bash
# Garry's Mod addon downloader script
# Published under public domain/CC0. 2024

# Sanity checks
NUMREGEX="^[0-9]*$"
if [[ -z ${*} ]]; then echo 'No ID(s) specified. Exiting.' >&2; exit 1; fi
for id; do
  if ! [[ ${id} =~ ${NUMREGEX} ]]; then
    echo "${id} is not a valid ID!" >&2
    FAIL=1
  fi
done

if ! hash jq; then echo "jq not found!" >&2; FAIL=1; fi
if ! hash curl; then echo "curl not found!" >&2; FAIL=1; fi
if ! hash wget; then echo "wget not found!" >&2; FAIL=1; fi
if ! hash ./DepotDownloader; then
  echo "DepotDownloader not found! Make sure it's in the same directory as this script." >&2
  FAIL=1
fi

if [[ ${FAIL} -eq 1 ]]; then
  echo "Please fix the above errors before continuing. Exiting."
  exit 1
fi

# Main script
for id; do
  echo "=============================================="
  echo "Checking if ${id} is valid..."
  # Save API response to variable and start parsing
  RESPONSE="$(curl -sd "itemcount=1&publishedfileids[0]=${id}" https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1 | jq -r '.response.publishedfiledetails[]')"
  # If fails or doesn't exist, .result will return anything but 1.
  RESULT="$(jq .result <<< "${RESPONSE}")"
  if [[ ${RESULT} -ne 1 ]]; then
    FAIL+=("${id}")
    echo "ERROR: ${id} returned code ${RESULT}! It probably doesn't exist." >&2
    continue
  fi

  # Collections are skipped (tells you to use download-collection.sh)
  CREATOR_APP_ID="$(jq -r .creator_app_id <<< "${RESPONSE}")"
  if [[ $CREATOR_APP_ID -eq 766 ]]; then
    echo "WARNING: ${id} is a collection! Use download-collection.sh to download." >&2
    SKIP+=("${id}")
    continue
  fi

  # Initialise metadata (we also fetch the workshop page as well for more metadata.)
  WEB_RESPONSE=$(curl -s "https://steamcommunity.com/sharedfiles/filedetails/?id=${id}")
  TITLE="$(jq -r .title <<< "${RESPONSE}")"
  CREATED="$(date -u -Iseconds -d @$(jq -r .time_created <<< "${RESPONSE}"))"
  UPDATED="$(date -u -Iseconds -d @$(jq -r .time_updated <<< "${RESPONSE}"))"
  CREATOR="$(jq -r .creator <<< "${RESPONSE}")"
  CATEGORY="$(jq -r '[.tags[].tag] | join(", ")' <<< "${RESPONSE}")"
  FILESIZE="$(jq -r .file_size <<< "${RESPONSE}" | numfmt --to iec --format "%8.2f" | sed 's/ //g')"
  MAIN_IMAGE="$(jq -r .preview_url <<< "${RESPONSE}")"
  # I really wish there was a better way to parse this...
  IMAGES=($(grep 'imw=5000' <<< "${WEB_RESPONSE}" | head -n -1 | cut -f8 -d\' | sed 's/\?imw=.*//g'))
  YOUTUBE_IDS=($(grep 'YOUTUBE_VIDEO_ID' <<< "${WEB_RESPONSE}" | cut -f2 -d\" | tr "\n" " "))

  # Check manifest with downloaded.txt to see if it was downloaded already.
  MANIFEST_ID="$(jq -r .hcontent_file <<< "${RESPONSE}")"
  if grep -s -q "${id}_${MANIFEST_ID}" downloaded.txt; then
    echo "WARNING: ${id} is already downloaded and up to date! Skipping." >&2
    UPTODATE+=("${id}")
    continue
  fi

  # Actually save metadata
  echo "Saving metadata..."
  mkdir -p "addons/${id}_${MANIFEST_ID}"
  # Raw .json response from Steam
  cat <<< "${RESPONSE}" > "addons/${id}_${MANIFEST_ID}/response.json"
  # Human readable version of above with additional info
  echo "Title: ${TITLE}" >> "addons/${id}_${MANIFEST_ID}/info.txt"
  echo "Creator: ${CREATOR}" >> "addons/${id}_${MANIFEST_ID}/info.txt"
  echo "Created: ${CREATED}" >> "addons/${id}_${MANIFEST_ID}/info.txt"
  echo "Updated: ${UPDATED}" >> "addons/${id}_${MANIFEST_ID}/info.txt"
  echo "Size: ${FILESIZE}" >> "addons/${id}_${MANIFEST_ID}/info.txt"
  if [[ -n ${YOUTUBE_IDS} ]]; then
    echo "YouTube IDs: ${YOUTUBE_IDS[@]}" >> "addons/${id}_${MANIFEST_ID}/info.txt"; fi
  echo -e "Images:\n${MAIN_IMAGE}" >> "addons/${id}_${MANIFEST_ID}/info.txt"
  printf "%s\n" "${IMAGES[@]}" >> "addons/${id}_${MANIFEST_ID}/info.txt"
  echo -e "Description:\n$(jq -r .description <<< "${RESPONSE}")" >> "addons/${id}_${MANIFEST_ID}/info.txt"

  echo "Fetching images..."
  (cd "addons/${id}_${MANIFEST_ID}"; wget -q -nc --show-progress --content-disposition "${MAIN_IMAGE}")

  # Gallery images, more often than not, use the *exact* same filename for every
  # image, causing a fair amount of trouble. I decided to rename each file
  # sequentially after each image to avoid this.
  if [[ -n ${IMAGES} ]]; then
    TEMPDIR=$(mktemp -p addons)
    for url in "${IMAGES[@]}"; do
      ((ITERATE+=1))
      wget -q -P "${TEMPDIR}" --show-progress --content-disposition "${url}"
      for file in "${TEMPDIR}"/*; do
        mv "${file}" "addons/${id}_${MANIFEST_ID}/${ITERATE}.${file##*.}"
      done
    done
    ITERATE=0
    rmdir "${TEMPDIR}"
  fi

  echo "Downloading addon ${id}: ${TITLE} [${FILESIZE}]..."
  ./DepotDownloader -app 4000 -pubfile "${id}" -dir addons/"${id}_${MANIFEST_ID}"
  # Under very fringe cases, DD can crash, so we have an error check here.
  # Either I forgot how to code, but check=$? isn't working. PIPESTATUS
  # works though, strangely enough.
  check="${PIPESTATUS[0]}"
  if [[ $check -ne 0 ]]; then
    echo "ERROR: DepotDownloader returned non-zero error code! ($check)" >&2
    FAIL+=("${id}")
    break
  fi

  echo "Looks good! Moving on."
  GOOD+=("${id}")
  # Add successful download to list
  echo "${id}_${MANIFEST_ID}" >> downloaded.txt
done

# Summary report
echo "DONE! ${#GOOD[@]} succeeded, ${#UPTODATE[@]} up to date, ${#FAIL[@]} failed, ${#SKIP[@]} skipped (collection)"
if [[ -n ${FAIL} ]]; then
  echo "Failed: $(IFS=","; echo "${FAIL[*]}" | sed 's/,/, /g')"; fi
if [[ -n ${SKIP} ]]; then
  echo "Skipped: $(IFS=","; echo "${SKIP[*]}" | sed 's/,/, /g')"; fi
