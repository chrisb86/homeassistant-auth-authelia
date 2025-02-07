#! /bin/sh

## auth_authelia.sh
## Authenticate a Home Assistant user against an authelia instance

## Copyright 2023 Christian Baer
## http://github.com/chrisb86/

## Permission is hereby granted, free of charge, to any person obtaining
## a copy of this software and associated documentation files (the
## "Software"), to deal in the Software without restriction, including
## without limitation the rights to use, copy, modify, merge, publish,
## distribute, sublicense, and/or sell copies of the Software, and to
## permit persons to whom the Software is furnished to do so, subject to
## the following conditions:

## The above copyright notice and this permission notice shall be
## included in all copies or substantial portions of the Software.

## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
## EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
## MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
## NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
## LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
## OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
## WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Inspired by https://kevo.io/posts/2023-01-29-authelia-home-assistant-auth/ by Kevin O'Connor

## This script expects 2 command line parametes. You can specifiy a third one.
## Usage: authelia_auth.sh AUTHELIA_DOMAIN HOMEASSISTANT_DOMAIN [AUTHELIA_HOMEASSISTANT_GROUP]

## AUTHELIA_DOMAIN: Domain of your authelia instance 
## For example:
##  - https://sso.example.com
##  - https://example.com/auth
##  - http://example.com:8443

## HOMEASSISTANT_DOMAIN: Domain of your home assistant instance as configured in authelia
## For example:
##  - https://ha.example.com
##  - http://homeassistant.example.com:8123

## AUTHELIA_HOMEASSISTANT_GROUP (optional): The authelia group name for users that are allowed to access home assistant
## For example:
##  - homassistant_users
##  - home_automation

## The variables ${username} and ${password} will be set to the environment by home assistant


## Populate variables from command line
AUTHELIA_DOMAIN="${1}"
HOME_ASSISTANT_DOMAIN="${2}"
AUTHELIA_HOME_ASSISTANT_GROUP="${3}"

## Usernames should be validated using a regular expression to be of
## a known format. Special characters will be escaped anyway, but it is
## generally not recommended to allow more than necessary.
USERNAME_PATTERN='^[a-z|A-Z|0-9|_|-|.]+$'

## Temporary file path for storing authelia headers
TMP_FILE_NAME="./tmp_curl_${username}_$(date +%s)"

## Log messages to stderr.
log() {
  echo "$1" >&2
}

err=0
group_permissions=false

## Check username and password are present and not malformed.
if [ -z "$username" ] || [ -z "$password" ]; then
  log "Need username and password environment variables."
  err=1
elif [ -n "$USERNAME_PATTERN" ]; then
  username_match=$(echo "$username" | sed -r "s/$USERNAME_PATTERN/x/")
  if [ "$username_match" != "x" ]; then
    log "Username '$username' has an invalid format."
    err=1
  fi
fi

[ $err -ne 0 ] && exit 2

## Authenticate with authelia and dump headers to temporary file
curl --silent \
  --request GET \
  --header "X-Original-URL: ${HOME_ASSISTANT_DOMAIN}" \
  --basic --user "${username}:${password}" \
  -D "${TMP_FILE_NAME}" \
  "${AUTHELIA_DOMAIN}/api/verify?auth=basic"

## Extract user name and groups from temporary file
homeassistant_name=$(grep remote-name < "${TMP_FILE_NAME}" | cut -d ' ' -f 2-)
homeassistant_groups=$(grep remote-groups < "${TMP_FILE_NAME}" | cut -d ' ' -f 2-)

## Delete temporary file
rm "${TMP_FILE_NAME}"

## Check if user name is set. Otherwise exit becaus we'r not authenticated
if [ -z "${homeassistant_name}" ]; then
    log "Could not authenticate with server."
    exit 3
else

  ## Check if home assistant group is specified

  if [ -n "${AUTHELIA_HOME_ASSISTANT_GROUP}" ]; then 

    ## Check if on the of the users group returned by server ,atches the specified home assistant group.
    ## If it has a match, grant group permissions
    for group in $(echo "${homeassistant_groups}" | sed -r 's/,/ /g'); do
      if [ "${group}" = "${AUTHELIA_HOME_ASSISTANT_GROUP}" ]; then
        group_permissions=true
      fi
    done
  else
    ## If no home assistant group is specified, grant group permissions
    group_permissions=true
  fi

  ## If group permissions are granted, echo the user name as expected by home assistant
  if [ "${group_permissions}" = true ]; then
    echo "name = ${homeassistant_name}"
  else
    ## Otherwise exit
    log "User has no permissions to access Home Assistant. Check group membership."
    exit 4
  fi
fi
