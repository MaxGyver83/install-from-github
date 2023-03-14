#!/bin/sh

# Script for downloading and installing/extracting the latest release
# of given GitHub projects (only Linux/amd64: deb/rpm/apk
# or zip/tar.gz/tar.xz).
#
# Dependencies: wget, grep, awk, tr, id, readelf, xargs
# Optional:
# - for deb: dpkg
# - for rpm: rpm
# - for apk: apk
# - for zip: unzip, zipfile, wc
# - for tar.gz or tar.xz: tar, gz/xz, wc

CACHE_DIR=~/.cache/install-from-github
DOWNLOAD_DIR=~/Downloads
BINARY_DIR=~/.local/bin

ACCEPT_FILTER='64'
IGNORE_FILTER_PACKAGE='arm|ppc'
IGNORE_FILTER_ARCHIVE='mac|macos|darwin|apple|win|bsd|arm|aarch|ppc|i686|sha256|deb$|rpm$|apk$|sig$'

WGET='wget'
WGET_ARGS='--continue --timestamping'
# TODO: --timestamping only available in GNU wget!?
# TODO: Use curl when wget is not available

RED=$(printf '\033[0;31m')
MAGENTA=$(printf '\033[0;35m')
YELLOW=$(printf '\033[0;33m')
BLUE=$(printf '\033[0;34m')
BOLD=$(printf '\033[1m')
RESET=$(printf '\033[0m')

header() { echo ; echo "${MAGENTA}$1${RESET}" ; }
warn()   { echo "  ${YELLOW}$1${RESET}" ; }
info()   { echo "  ${BLUE}$1${RESET}" ; }
error()  { echo "${RED}$1${RESET}" >&2 ; }
die()    { error "$1" ; exit 1 ; }

usage() {
    echo "Download latest deb/rpm/apk package (if available) or archive otherwise
for every given GITHUB_PROJECT to ~/Download/ and install/extract it.

USAGE
  ./install-from-github.sh [OPTIONS] GITHUB_PROJECTS

EXAMPLE
  ./install-from-github.sh -v -a BurntSushi/ripgrep sharkdp/fd

OPTIONS
  -h, --help                       show help
  -v, --verbose                    print output of wget command
  -vv, --extra-verbose             print every command (set -x), implies -v
  -a, --archives-only              skip searching for deb/rpm/apk packages first
  -m, --prefer-musl                pick musl package/archive if applicable and
                                   available
  -p, --project-file projects.txt  read projects from file projects.txt
                                   (one project per line)
  -d, --dev                        development mode: use already downloaded
                                   asset lists (if possible) and skip download
                                   of packages/archives (for testing filters)

This script's homepage: <https://github.com/MaxGyver83/install-from-github/>
"
}

while [ "$#" -gt 0 ]; do case $1 in
    -h|--help) usage; exit 0; shift;;
    -v|--verbose) VERBOSE=1; shift;;
    -vv|--extra-verbose) EXTRA_VERBOSE=1; VERBOSE=1; shift;;
    -a|--archives-only) ARCHIVES_ONLY=1; shift;;
    -m|--prefer-musl) PREFER_MUSL=1; shift;;
    -d|--dev) DEV=1; shift;;
    -p|--project-file) PROJECT_FILE="$(realpath "$2")"; shift; shift;;
    *) break;
esac; done

[ "$(id -u)" -eq 0 ] && IS_ROOT=1
[ $VERBOSE ] || WGET="$WGET -o /dev/null"
[ $EXTRA_VERBOSE ] && set -x

if [ -f /etc/debian_version ]; then
    PACKAGE_FILETYPE="deb"
    INSTALL_CMD="dpkg -i"
elif [ -f /etc/redhat-release ]; then
    PACKAGE_FILETYPE="rpm"
    INSTALL_CMD="rpm -i"
elif [ -f /etc/alpine-release ]; then
    PACKAGE_FILETYPE="apk"
    INSTALL_CMD="apk add --allow-untrusted"
    PREFER_MUSL=1
fi

if [ "$INSTALL_CMD" ] && [ ! $IS_ROOT ]; then
    if command -v sudo > /dev/null 2>&1; then
        INSTALL_CMD="sudo $INSTALL_CMD"
    elif command -v doas > /dev/null 2>&1; then
        INSTALL_CMD="doas $INSTALL_CMD"
    fi
fi


is_binary() {
    readelf --file-header "$1" > /dev/null 2>&1
}

is_in_PATH() {
    case "$PATH" in
        *":$1:"*) return 0 ;;
        *":$1") return 0 ;;
        "$1:"*) return 0 ;;
        *) return 1 ;;
    esac
}

download_asset_list() {
    project="$1"
    filename="$2"
    # in development mode, use cached asset list if available
    [ $DEV ] && [ -f "$filename" ] && return 0
    info "Downloading asset list ..."
    $WGET -O "$filename" "https://api.github.com/repos/$project/releases/latest"  || return 1
}

download_and_install_package() {
    project="$1"
    filename="$2"
    all_packages="$(grep browser_download_url "$filename" \
        | awk '{ print $2 }' | tr -d '"' \
        | grep -E "\.${PACKAGE_FILETYPE}\$")"
    if [ -z "$all_packages" ]; then
        warn "No ${PACKAGE_FILETYPE} package available. Checking for archive ..."
        return 1
    fi
    count="$(echo "$all_packages" | wc -l)"
    if [ "$count" -gt 1 ]; then
        # only 64 bit, no arm, ppc
        package="$(echo "$all_packages" \
            | grep -E "$ACCEPT_FILTER" \
            | grep -E -i -v "$IGNORE_FILTER_PACKAGE")"
    else
        package="$all_packages"
    fi

    count="$(echo "$package" | wc -l)"
    if [ "$count" -gt 1 ]; then
        if [ $PREFER_MUSL ]; then
            package="$(echo "$package" | grep musl)"
        else
            package="$(echo "$package" | grep -v musl)"
        fi
    fi

    count="$(echo "$package" | wc -l)"
    if [ -z "$package" ]; then
        echo "  Skipped packages:
        $all_packages"
        warn "${PACKAGE_FILETYPE}: No matches left after filtering. Checking for archive ..."
        return 1
    elif [ "$count" -gt 1 ]; then
        echo "$package"
        warn "${PACKAGE_FILETYPE}: Too many matches left after filtering. Checking for archive ..."
        return 1
    fi
    echo "$package"
    [ $DEV ] && return 0
    info "Downloading $(basename "$package") ..."
    $WGET $WGET_ARGS "$package"
    echo "  $INSTALL_CMD $(basename "$package")"
    if ! $INSTALL_CMD "$(basename "$package")"; then
        error "Installation failed!"
        return 1
    fi
}

extract_archive() {
    case $1 in
        *.tar.gz) filetype='.tar.gz'; cmd='tar -xzf'; dir_flag='-C' ;;
        *.tar.xz) filetype='.tar.xz'; cmd='tar -xJf'; dir_flag='-C' ;;
        *.zip)    filetype='.zip';    cmd='unzip -q'; dir_flag='-d' ;;
        *)        warn "Unknown archive file type!" ; return ;;
    esac

    # extract into new subfolder
    folder="${filename%"$filetype"}"
    # remove $folder first if it already exists
    [ -d "$folder" ] && rm -rf "$folder"
    mkdir "$folder"
    info "Extracting $filename into $folder ..."
    $cmd "$filename" $dir_flag "$folder"
    # copy executables into $BINARY_DIR
    find "$folder" -executable -type f -print0 | xargs -0 -I{} cp {} $BINARY_DIR
    executables="$(find "$folder" -executable -type f)"
    if [ -n "$executables" ]; then
        filelist="$(echo "$executables" | while read -r file; do basename "$file"; done | xargs)"
        info "Copied $BOLD$filelist$RESET$BLUE to $BINARY_DIR"
    fi
}

download_and_extract_archive() {
    project="$1"
    filename="$2"

    archive=$(grep browser_download_url "$filename" \
        | awk '{ print $2 }' | tr -d '"' \
        | grep -e "$ACCEPT_FILTER" \
        | grep -E -i -v "$IGNORE_FILTER_ARCHIVE")
    count="$(echo "$archive" | wc -l)"
    if [ "$count" -gt 1 ]; then
        if [ $PREFER_MUSL ]; then
            archive="$(echo "$archive" | grep musl)"
        else
            archive="$(echo "$archive" | grep -v musl)"
        fi
    fi
    count="$(echo "$archive" | wc -l)"
    if [ -z "$archive" ]; then
        warn "archive: No matches left after filtering. Skipping $project."
        return 1
    elif [ "$count" -gt 1 ]; then
        echo "$archive"
        warn "archive: Too many matches left after filtering. Skipping $project."
        return 1
    fi
    echo "$archive"
    [ $DEV ] && return 0
    filename="$(basename "$archive")"
    [ -f "$DOWNLOAD_DIR/$filename" ] && rm -rf "${DOWNLOAD_DIR:?}/$filename"
    $WGET $WGET_ARGS "$archive"
    mkdir -p $BINARY_DIR
    if is_binary "$filename"; then
        [ -x "$filename" ] || chmod +x "$filename"
        cp "$filename" $BINARY_DIR && info "Copied $BOLD$filename$RESET$BLUE into $BINARY_DIR."
    else
        extract_archive "$filename"
    fi
    AT_LEAST_ON_BINARY_COPIED=1
}


# shellcheck disable=SC2015 # die when either mkdir or cd fails
mkdir -p "$DOWNLOAD_DIR" && cd "$DOWNLOAD_DIR" \
    || die "Could not create/change into $DOWNLOAD_DIR!"

mkdir -p "$CACHE_DIR" \
    || die "Could not create $CACHE_DIR!"

if [ "$PROJECT_FILE" ]; then
    # ignore comments (everything after '#')
    projects="$(grep -o '^[^#]*' "$PROJECT_FILE")"
elif [ -n "$1" ]; then
    projects="$*"
else
    usage
    exit 0
fi

for project in $projects; do
    header "$project"
    filename="$CACHE_DIR/$(echo "$project" | tr / _)_assets.json"
    download_asset_list "$project" "$filename" \
        || die "Couldn't download asset file from GitHub!"
    [ -s "$filename" ] || { warn "$filename is empty!"; continue; }
    if [ "$INSTALL_CMD" ] && [ ! $ARCHIVES_ONLY ]; then
        download_and_install_package "$project" "$filename" && continue
    fi
    download_and_extract_archive "$project" "$filename"
done

if [ $AT_LEAST_ON_BINARY_COPIED ] && ! is_in_PATH "$BINARY_DIR"; then
    echo
    warn "$BINARY_DIR is not in \$PATH! Add it with
PATH=\"$BINARY_DIR:\$PATH\""
fi
