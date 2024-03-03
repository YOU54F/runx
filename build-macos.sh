#!/bin/sh

RELEASE_DATE=20240215
RUBY_VERSION=3.1.4
PLATFORM=osx
ARCH=x86_64
LEGACY=""

while getopts "d:v:p:a:l:" flag; do
    case "${flag}" in
        d) RELEASE_DATE=${OPTARG} ;;
        v) RUBY_VERSION=${OPTARG} ;;
        p) PLATFORM=${OPTARG} ;;
        a) ARCH=${OPTARG} ;;
        l) LEGACY=${OPTARG} ;;
        *) echo "Unexpected option ${flag}"; exit 1 ;;
    esac
done

rm -rf runtime
export GOOS=darwin
if [ "${ARCH}" = "arm64" ]; then
    export GOARCH=arm64
else
    export GOARCH=amd64
fi
if [ "${LEGACY}" != "" ]; then
    export LEGACY_SRC=1
    exec ./build-unix.sh "${LEGACY}"
else
    exec ./build-unix.sh "rel-${RELEASE_DATE}/traveling-ruby-${RELEASE_DATE}-${RUBY_VERSION}-${PLATFORM}-${ARCH}.tar.gz"
fi


# https://github.com/YOU54F/traveling-ruby/releases/download/rel-20240215/traveling-ruby-20240215-2.6.10-linux-arm64.tar.gz
# exec ./build-unix.sh 'traveling-ruby-20150210-2.1.5-osx.tar.gz'
# exec ./build-unix.sh 'traveling-ruby-20150715-2.2.2-osx.tar.gz'
# exec ./build-unix.sh 'traveling-ruby-20210206-2.4.10-osx.tar.gz'

