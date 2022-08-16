# Install from GitHub

## What is this script good for?

TL;DR: Run `install-from-github.sh` with a list of GitHub projects to download and install/extract their latest deb/rpm/apk packages or binary archives.

Whenever I start working on a new Linux system (p.e. a server in a cluster, a VPS, a project-wide development Docker container at work) for longer than a few minutes, I want to install some tools that I'm used to. And most of these systems have Ubuntu LTS installed, with old software in their repositories and some tools not even available. In such cases, I go to GitHub.com and search the latest release's deb package matching my system, download it and install it (with `dpkg`). Sometimes, there is no deb package available, and I have to download and extract the (correct) zip/tar.gz/tar.xz archive. There is a lot of typing, clicking, copying and pasting involved. And there is no link that points always to the latest 64-bit deb package (of a project). That's why I made this script to automate this task.

This script is for 64-bit (`x86_64`) Linux systems only. It should be easy to make it work on BSD/macOS/arm systems, too. (The filters would be slightly different on such systems.)

![Screenshot of install-from-github.sh](https://maximilian-schillinger.de/img/install-from-github.png "Screenshot")

## How to use

Just clone this repository and run the script with the GitHub projects you want to install as parameters:

```sh
git clone https://github.com/MaxGyver83/install-from-github
cd install-from-github
./install-from-github.sh BurntSushi/ripgrep sharkdp/fd
# or
./install-from-github.sh -p projects.txt
```

... or without `git clone`:

```sh
wget https://raw.githubusercontent.com/MaxGyver83/install-from-github/main/install-from-github.sh
chmod +x install-from-github.sh
./install-from-github.sh BurntSushi/ripgrep sharkdp/fd
```

This script will prefer deb/rpm/apk packages and install them with `[sudo] dpkg -i PACKAGE` (in case you are using Debian/Ubuntu, RedHat or Alpine) and download + extract binary archives as a fallback. If you prefer binary archives (maybe because you don't have sudo rights), use the option `--archives-only` (or short: `-a`):

```sh
./install-from-github.sh -a BurntSushi/ripgrep sharkdp/fd
```

Add `-m`/`--prefer-musl` if you prefer musl over glibc variants (when applicable). This is the default behaviour in Alpine Linux.

### Notes

* Dependencies: wget, grep, awk, tr (and dpkg or unzip or tar + gz or xz)
* If the script doesn't work as expected, try calling it with `-v` or `-vv`.
* On Debian/Ubuntu/RedHat/Alpine: This script will try installing deb/rpm/apk packages using sudo or doas, asking for your password (cancel with Ctrl-c if you want to install later).
