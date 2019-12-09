#!/usr/bin/env bash
#
# multiwerf publisher utility
# Create github release and upload go binary as asset.
#

set -e

## Global variables

#BINTRAY_AUTH=             # bintray auth user:TOKEN
BINTRAY_SUBJECT=flant      # bintray organization
BINTRAY_REPO=multiwerf     # bintray repository
BINTRAY_PACKAGE=multiwerf  # bintray package in repository

#NO_PRERELEASE=            # This is not a pre release

#GITHUB_TOKEN=             # github API token
GITHUB_OWNER=flant         # github user/org
GITHUB_REPO=multiwerf      # github repository

#GIT_TAG=                  # git tag value i.e. from $CIRCLE_TAG or $CI_COMMIT_TAG or $TRAVIS_TAG
GIT_REMOTE=origin          # can be changed to `upstream` if needed

RELEASE_BUILD_DIR=$(pwd)/release-build


main() {
  if [ -z "$BINTRAY_AUTH"  ] ; then
    echo "Error! No bintray token specified!"
    exit 1
  fi

  curlPath=
  check_curl || (echo "$0: cannot find curl command" && exit 2)

  VERSION=
  if [ "x$1" == "xversion" ] ; then
    if [ -n "$BINTRAY_AUTH" ] ; then
      VERSION=$2
      TAG_RELEASE_MESSAGE="\"$VERSION release\""
      GIT_TAG="v${VERSION}"
      ( bintray_create_version  && echo "Bintray: Version $VERSION created" ) || ( exit 1 )
    fi
    exit 0
  fi

  if [ "x$1" == "xpublish" ] ; then
    if [ -n "$BINTRAY_AUTH" ] ; then
      VERSION=$2
      TAG_RELEASE_MESSAGE="\"$VERSION release\""
      GIT_TAG="v${VERSION}"

        ( bintray_upload_file_into_version $3 $4 ) || ( exit 1 )
    fi

    exit 0
  fi

  if [ "x$1" == "xrelease-github" ] ; then
    parse_args "$@" || (usage && exit 1)

    # get git path
    gitPath=
    check_git || (echo "$0: cannot find git command" && exit 2)

    #TAG_LOCAL_SHA=$($gitPath for-each-ref --format='%(objectname)' refs/tags/$GIT_TAG)
    #TAG_REMOTE_SHA=$($gitPath ls-remote --tags $GIT_REMOTE refs/tags/$GIT_TAG | cut -f 1)

    #if [ "x$TAG_LOCAL_SHA" != "x$TAG_REMOTE_SHA" ] ; then
    #  echo "CRITICAL: Tag $GIT_TAG should be pushed to $GIT_REMOTE before creating new release"
    #  exit 1
    #fi

    # $gitPath checkout -f $GIT_TAG || (echo "$0: git checkout error" && exit 2)

    # version for release without v prefix
    VERSION=${GIT_TAG#v}
    # message for github release and bintray version description
    # change to *contents to get commit message
    TAG_RELEASE_MESSAGE=$($gitPath for-each-ref --format="%(contents)" refs/tags/$GIT_TAG | jq -R -s '.' )
    #TAG_RELEASE_MESSAGE="\"\""

    source $(dirname $0)/go-release-build.sh $VERSION

    echo "Upload to bintray version $VERSION for git tag $GIT_TAG"
    if [ -n "$BINTRAY_AUTH" ] ; then
      ( bintray_create_version && echo "Bintray: Version $VERSION created" ) || ( exit 1 )

      cd $RELEASE_BUILD_DIR
      for filename in * ; do
        echo Upload $filename
        ( bintray_upload_file_into_version $filename $VERSION/$filename ) || ( exit 1 )
      done
    fi

    if [ -n "$GITHUB_TOKEN" ] ; then
      ( github_create_release && echo "Github: Release for tag $GIT_TAG created" ) || ( exit 1 )
    fi


    exit 0
  fi

}

bintray_create_version() {
PAYLOAD=$(cat <<- JSON
  {
     "name": "${VERSION}",
     "desc": ${TAG_RELEASE_MESSAGE},
     "vcs_tag": "${GIT_TAG}"
  }
JSON
)
  curlResponse=$(mktemp)
  status=$(curl -s -w %{http_code} -o $curlResponse \
      --request POST \
      --user $BINTRAY_AUTH \
      --header "Content-type: application/json" \
      --data "$PAYLOAD" \
      https://api.bintray.com/packages/${BINTRAY_SUBJECT}/${BINTRAY_REPO}/${BINTRAY_PACKAGE}/versions
  )

  # return if version is already exists
  conflict=$(grep 'Conflict Creating Version' $curlResponse)
  if [ -n "$conflict" ] ; then
    return 0
  fi

  echo "Bintray create version: curl return status $status with response"
  cat $curlResponse
  echo
  rm $curlResponse

  ret=0
  if [ "x$(echo $status | cut -c1)" != "x2" ]
  then
    ret=1
  fi

  return $ret
}

# upload file to $GIT_TAG version
bintray_upload_file_into_version() {
  UPLOAD_FILE_PATH=$1
  DESTINATION_PATH=$2

  curlResponse=$(mktemp)
  status=$(curl -s -w %{http_code} -o $curlResponse \
      --header "X-Bintray-Publish: 1" \
      --header "X-Bintray-Override: 1" \
      --header "X-Bintray-Package: $BINTRAY_PACKAGE" \
      --header "X-Bintray-Version: $VERSION" \
      --header "Content-type: application/binary" \
      --request PUT \
      --user $BINTRAY_AUTH \
      --upload-file $UPLOAD_FILE_PATH \
      https://api.bintray.com/content/${BINTRAY_SUBJECT}/${BINTRAY_REPO}/$DESTINATION_PATH
  )

  echo "Bintray upload $DESTINATION_PATH: curl return status $status with response"
  cat $curlResponse
  echo
  rm $curlResponse

  ret=0
  if [ "x$(echo $status | cut -c1)" != "x2" ]
  then
    ret=1
  else
    dlUrl="https://dl.bintray.com/${BINTRAY_SUBJECT}/${BINTRAY_REPO}/${DESTINATION_PATH}"
    echo "Bintray: $DESTINATION_PATH uploaded to ${dlURL}"
  fi

  return $ret
}

github_create_release() {
  prerelease="true"
  if [[ "$NO_PRERELEASE" == "yes" ]] ; then
    prerelease="false"
    echo "# Creating release $GIT_TAG"
  else
    echo "# Creating pre-release $GIT_TAG"
  fi

  GHPAYLOAD=$(cat <<- JSON
{
  "tag_name": "$GIT_TAG",
  "name": "multiwerf $VERSION",
  "body": $TAG_RELEASE_MESSAGE,
  "draft": false,
  "prerelease": $prerelease
}
JSON
)

  curlResponse=$(mktemp)
  status=$(curl -s -w %{http_code} -o $curlResponse \
      --request POST \
      --header "Authorization: token $GITHUB_TOKEN" \
      --header "Accept: application/vnd.github.v3+json" \
      --data "$GHPAYLOAD" \
      https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases
  )

  echo "Github create release: curl return status $status with response"
  cat $curlResponse
  echo
  rm $curlResponse

  ret=0
  if [ "x$(echo $status | cut -c1)" != "x2" ]
  then
    ret=1
  fi

  return $ret
}

check_git() {
  gitPath=$(which git) || return 1
}

check_curl() {
  curlPath=$(which curl) || return 1
}



usage() {
printf " Usage: $0 COMMAND ARGS

Commands:
    version <version>
            Creates specified version in bintray

    publish <version> <local file path> <repo path>
            Upload and publish file in bintray version

    release ARGS
            Build, create version in bintray, upload
            binaries to bintray, create github release.


Arguments:

    --no-prerelease
    env: NO_PRERELEASE
            This is final release, not a prerelease. Prerelease will be created by default.
            Can be changed manually later in the github UI.

    --tag
            Release is a tag based. Tag should be present if gh-token specified.

    --github-token TOKEN
    env: GITHUB_TOKEN
            Write access token for github. No github actions if no token specified.

    --bintray-auth user:TOKEN
    env: BINTRAY_AUTH
            User and token for upload to bintray.com. No bintray actions if no token specified.

    --help|-h
            Print help

"
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --tag)
        GIT_TAG="$2"
				shift
        ;;
      --github-token)
        GITHUB_TOKEN="$2"
        shift
        ;;
      --bintray-auth)
        BINTRAY_AUTH="$2"
        shift
        ;;
      --no-prerelease)
        NO_PRERELEASE="yes"
        ;;
      --help|-h)
        return 1
        ;;
      --*)
        echo "Illegal option $1"
        return 1
        ;;
    esac
    shift $(( $# > 0 ? 1 : 0 ))
  done

  [ -z "$GIT_TAG" ] && return 1 || return 0
}

# wait for full file download if executed as
# $ curl | sh
main "$@"
