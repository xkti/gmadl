#!/bin/bash
# Garry's Mod addon collection helper
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
  echo "Collection wrapper script -- mostly working"
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

  # Check if it's actually a collection or not.
  CREATOR_APP_ID="$(jq -r .creator_app_id <<< "${RESPONSE}")"
  if [[ $CREATOR_APP_ID -ne 766 ]]; then
    echo "ERROR: ${id} is not a collection!" >&2
    FAIL+=("${id}")
    continue
  fi

  COLLECTION=($(curl -sd "collectioncount=1&publishedfileids[0]=${id}" https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/ | jq -r '.response.collectiondetails[] | .children[] | select(.filetype == 0) | .publishedfileid' | tr '\n' ' '))
  echo "Calling download-addon.sh to download ${#COLLECTION[@]} addons..."
  ./download-addon.sh ${COLLECTION[@]}
done
