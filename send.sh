#!/bin/bash
# This original source of this code: https://github.com/DiscordHooks/travis-ci-discord-webhook
# The same functionality from TravisCI is needed for Github Actions
#
# For info on the GITHUB prefixed variables, visit:
# https://help.github.com/en/articles/virtual-environments-for-github-actions#environment-variables

AVATAR="https://github.com/actions.png"

# More info: https://www.gnu.org/software/bash/manual/bash.html#Shell-Parameter-Expansion
case ${1,,} in
  "success" )
    EMBED_COLOR=3066993
    STATUS_MESSAGE="Passed"
    THUMBNAIL_URL="https://raw.githubusercontent.com/elendil7/github-actions-discord-webhook/master/public/icons/success.png"
    ;;

  "failure" )
    EMBED_COLOR=15158332
    STATUS_MESSAGE="Failed"
    THUMBNAIL_URL="https://raw.githubusercontent.com/elendil7/github-actions-discord-webhook/master/public/icons/failure.png"
    ;;

  * )
    STATUS_MESSAGE="Status Unknown"
    EMBED_COLOR=0
    THUMBNAIL_URL="https://raw.githubusercontent.com/elendil7/github-actions-discord-webhook/master/public/icons/unknown.png"
    ;;
esac

shift

if [ $# -lt 1 ]; then
  echo -e "WARNING!!\nYou need to pass the WEBHOOK_URL environment variable as the second argument to this script.\nFor details & guide, visit: https://github.com/DiscordHooks/github-actions-discord-webhook" && exit
fi

AUTHOR_NAME="$(git log -1 "$GITHUB_SHA" --pretty="%aN")"
COMMITTER_NAME="$(git log -1 "$GITHUB_SHA" --pretty="%cN")"
COMMIT_SUBJECT="$(git log -1 "$GITHUB_SHA" --pretty="%s")"
COMMIT_MESSAGE="$(git log -1 "$GITHUB_SHA" --pretty="%b")" | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g'
COMMIT_URL="https://github.com/$GITHUB_REPOSITORY/commit/$GITHUB_SHA"

# If, for example, $GITHUB_REF = refs/heads/feature/example-branch
# Then this sed command returns: feature/example-branch
BRANCH_NAME="$(echo $GITHUB_REF | sed 's/^[^/]*\/[^/]*\///g')"
REPO_URL="https://github.com/$GITHUB_REPOSITORY"
BRANCH_OR_PR="Branch"
BRANCH_OR_PR_URL="$REPO_URL/tree/$BRANCH_NAME"
ACTION_URL="$COMMIT_URL/checks"
COMMIT_OR_PR_URL=$COMMIT_URL
if [ "$AUTHOR_NAME" == "$COMMITTER_NAME" ]; then
  CREDITS="$AUTHOR_NAME authored & committed"
else
  CREDITS="$AUTHOR_NAME authored & $COMMITTER_NAME committed"
fi

if [ "$GITHUB_EVENT_NAME" == "pull_request" ]; then
	BRANCH_OR_PR="Pull Request"
	
	PR_NUM=$(sed 's/\/.*//g' <<< $BRANCH_NAME)
	BRANCH_OR_PR_URL="$REPO_URL/pull/$PR_NUM"
	BRANCH_NAME="#${PR_NUM}"
	
	# Call to GitHub API to get PR title
	PULL_REQUEST_ENDPOINT="https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$PR_NUM"
	
	WORK_DIR=$(dirname ${BASH_SOURCE[0]})
	PULL_REQUEST_TITLE=$(ruby $WORK_DIR/get_pull_request_title.rb $PULL_REQUEST_ENDPOINT)

  # Sanitize the COMMIT_SUBJECT field in case it exceeds length (typically due to error when fetching PR title)
  MAX_TITLE_LENGTH=256
  COMMIT_SUBJECT=""
  if (( ${#COMMIT_SUBJECT} > MAX_TITLE_LENGTH )); then
    COMMIT_SUBJECT="Error: Title exceeds character limit"
  else
	  COMMIT_SUBJECT=$PULL_REQUEST_TITLE
  fi

  # Sanitize the commit subject; remove everything except characters allowed in a discord embed title
  # https://discordapp.com/developers/docs/resources/channel#embed-limits
  COMMIT_SUBJECT=$(echo "$COMMIT_SUBJECT" | sed -E 's/[^a-zA-Z0-9!"#$%&\'"'"'()*+,\-./:;<=>?@\[\]^_`{|}~ ]//g')

	COMMIT_MESSAGE="Pull Request #$PR_NUM"
	ACTION_URL="$BRANCH_OR_PR_URL/checks"
	COMMIT_OR_PR_URL=$BRANCH_OR_PR_URL
fi

TIMESTAMP=$(date -u +%FT%TZ)
WEBHOOK_DATA='{
  "avatar_url": "'$AVATAR'",
  "embeds": [ {
    "color": '$EMBED_COLOR',
    "author": {
      "name": "'$(echo "$STATUS_MESSAGE: $WORKFLOW_NAME ($HOOK_OS_NAME) - $GITHUB_REPOSITORY" | cut -c 1-256)'",
      "url": "'$ACTION_URL'",
      "icon_url": "'$AVATAR'"
    },
    "title": "'$COMMIT_SUBJECT'",
    "url": "'$COMMIT_OR_PR_URL'",
    "description": "'$(echo "${COMMIT_MESSAGE//$'\n'/ }" | cut -c 1-4096)\\n\\n$CREDITS'",
    "fields": [
      {
        "name": "Commit",
        "value": "'"[\`${GITHUB_SHA:0:7}\`](${COMMIT_URL})"'",
        "inline": true
      },
      {
        "name": "'"$BRANCH_OR_PR"'",
        "value": "'"[\`${BRANCH_NAME}\`](${BRANCH_OR_PR_URL})"'",
        "inline": true
      }
    ],
    "thumbnail": {
      "url": "'$THUMBNAIL_URL'"
    },
    "timestamp": "'$TIMESTAMP'"
  } ]
}'
for ARG in "$@"; do
  echo -e "[Webhook]: Sending webhook to Discord...\\n";

  RESPONSE=$(curl --fail --progress-bar -A "GitHub-Actions-Webhook" -H Content-Type:application/json -H X-Author:k3rn31p4nic#8383 -d "${WEBHOOK_DATA//	/ }" -w "\n%{http_code}" -o /dev/null "$ARG")
  STATUS_CODE=$(echo "$RESPONSE" | tail -n1)
  ERROR_RESPONSE=$(echo "$RESPONSE" | sed '$d')

  # Check for good status code response. If error, show error message.
  if [ "$STATUS_CODE" -eq 200 ] || [ "$STATUS_CODE" -eq 204 ] || [ "$STATUS_CODE" -eq 201 ] || [ "$STATUS_CODE" -eq 202 ]; then
    echo -e "[Webhook]: Successfully sent the webhook."
  else
    echo -e "\\n[Webhook]: Unable to send webhook. Status code: $STATUS_CODE, error: $ERROR_RESPONSE"
    # Log the webhook body for diagnostic purposes.
    echo -e "\\n[Webhook]: Webhook was: $WEBHOOK_DATA"
  fi
done