#!/bin/sh

set -x

package=$1

if [ ! -d runtime ]; then
  mkdir -p runtime/lib/ruby
  mkdir -p runtime/lib/app
  if [ "${LEGACY_SRC:-0}" = 1 ]; then
    curl -L --fail "https://d6r77u77i8pq3.cloudfront.net/releases/$package" | tar -zxv -C runtime/lib/ruby
  else
    curl -L --fail "https://github.com/YOU54F/traveling-ruby/releases/download/$package" | tar -zxv -C runtime/lib/ruby
  fi
fi

cp runx.rb runtime/lib/app/runx.rb
$(which go-bindata) runtime/...

version=`git tag | tail -n1`
commit=`git rev-parse HEAD`
payloadHash=`shasum -a 256 bindata.go | awk '{ print $1 }' | head -c 8`
go build -ldflags "-w -s -X main.version=$version -X main.commit=$commit -X main.payloadDir=$version.$payloadHash" -o runx
