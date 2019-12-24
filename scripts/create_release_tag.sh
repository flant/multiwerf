#!/bin/bash

set -eo pipefail -o nounset

for f in $(find scripts/lib -type f -name "*.sh"); do
  source $f
done

if [ -z "${1-}" ] ; then
  echo "Usage: $0 VERSION"
  echo
  exit 1
fi

if [ "$1" = ":experimental" ] ; then
  BINTRAY_REPO=multiwerf-experimental
  VERSION="v$(date +%y.%m.%d-%H.%M.%S)"
else
  BINTRAY_REPO=multiwerf-nonexistent # FIXME: remove durak-guard just before release when master will be ready for stable
  VERSION=$1
fi

DIR="$(dirname "${0}")"

TAG_TEMPLATE="$DIR/git_tag_template.md"

LATEST_TAG="$(git tag -l --sort=-taggerdate | head -n1)"
echo "latest tag is ${LATEST_TAG}"
CHANGELOG_TEXT="$(git log --pretty="%s" HEAD...${LATEST_TAG})"
if [[ -n $CHANGELOG_TEXT ]] ; then
  CHANGELOG_TEXT="$(echo "$CHANGELOG_TEXT" | grep -v '^Merge' | sed 's/^/- /')"
fi
echo "CHANGELOG_TEXT = ${CHANGELOG_TEXT}"

BINTRAY_REPO="${BINTRAY_REPO}" VERSION="${VERSION}" CHANGELOG_TEXT="${CHANGELOG_TEXT}" envsubst < ${TAG_TEMPLATE} | git tag --annotate --file - --edit $VERSION

git push --tags
