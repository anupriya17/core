#!/bin/bash -e
set -e
has() {
  type "$1" > /dev/null 2>&1
}

# Redirect stdout ( > ) into a named pipe ( >() ) running "tee"
# exec > >(tee /tmp/installlog.txt)

# Without this, only stdout would be captured - i.e. your
# log file would not contain any error messages.
exec 2>&1

if has "wget"; then
  DOWNLOAD() {
    wget --no-check-certificate -nc -O "$2" "$1"
  }
elif has "curl"; then
  DOWNLOAD() {
    curl -sSL -o "$2" "$1"
  }
else
  echo "Error: you need curl or wget to proceed" >&2;
  exit 1
fi

C9_DIR=$HOME/.c9
if [[ ${1-} == -d ]]; then
    C9_DIR=$2
    shift 2
fi

# Check if C9_DIR exists
if [ ! -d "$C9_DIR" ]; then
  mkdir -p $C9_DIR
fi

VERSION=1
NODE_VERSION=v14.4.0
#NODE_VERSION_ARM_PI=v0.10.28
NPM=$C9_DIR/node/bin/npm
YARN=yarn
NODE=$C9_DIR/node/bin/node

export TMP=$C9_DIR/tmp
export TMPDIR=$TMP

PYTHON=python3

# node-gyp uses sytem node or fails with command not found if
# we don't bump this node up in the path
PATH="$C9_DIR/node/bin/:$C9_DIR/node_modules/.bin:$PATH"

start() {
  if [ $# -lt 1 ]; then
    start base
    return
  fi

  check_deps

  # Try to figure out the os and arch for binary fetching
  local uname="$(uname -s)"
  local os=
  local arch="$(uname -m)"
  case "$uname" in
    Linux*) os=linux ;;
    Darwin*) os=darwin ;;
    SunOS*) os=sunos ;;
    FreeBSD*) os=freebsd ;;
    CYGWIN*) os=windows ;;
    MINGW*) os=windows ;;
  esac
  case "$arch" in
    *arm64*) arch=arm64 ;;
    *aarch64*) arch=arm64 ;;
    *armv6l*) arch=armv6l ;;
    *armv7l*) arch=armv7l ;;
    *x86_64*) arch=x64 ;;
    *i*86*) arch=x86 ;;
    *)
      echo "Unsupported Architecture: $os $arch" 1>&2
      exit 1
    ;;
  esac

  if [ "$arch" == "x64" ] && [[ $HOSTTYPE == i*86 ]]; then
    arch=x86 # check if 32 bit bash is installed on 64 bit kernel
  fi

  if [ "$os" != "linux" ] && [ "$os" != "darwin" ]; then
    echo "Unsupported Platform: $os $arch" 1>&2
    exit 1
  fi

  case $1 in
    "help" )
      echo
      echo "Cloud9 Installer"
      echo
      echo "Usage:"
      echo "    install help                       Show this message"
      echo "    install install [name [name ...]]  Download and install a set of packages"
      echo "    install ls                         List available packages"
      echo
    ;;

    "ls" )
      echo "!node - Node.js"
      echo "!tmux - TMUX"
      echo "!nak - NAK"
      echo "!ptyjs - pty.js"
      echo "!collab - collab"
      echo "coffee - Coffee Script"
      echo "less - Less"
      echo "sass - Sass"
      echo "typescript - TypeScript"
      echo "stylus - Stylus"
      # echo "go - Go"
      # echo "heroku - Heroku"
      # echo "rhc - RedHat OpenShift"
      # echo "gae - Google AppEngine"
    ;;

    "install" )
      shift

      # make sure dirs are around
      mkdir -p "$C9_DIR"/bin
      mkdir -p "$C9_DIR"/tmp
      mkdir -p "$C9_DIR"/node_modules

      # install packages
      while [ $# -ne 0 ]
      do
        if [ "$1" == "tmux" ]; then
          cd "$C9_DIR"
          time tmux_install $os $arch
          shift
          continue
        fi
        cd "$C9_DIR"
        time eval ${1} $os $arch
        shift
      done

      # finalize
      pushd "$C9_DIR"/node_modules/.bin
      for FILE in "$C9_DIR"/node_modules/.bin/*; do
        FILE=$(readlink "$FILE")
        # can't use the -i flag since it is not compatible between bsd and gnu versions
        sed -e's/#!\/usr\/bin\/env node/#!'"${NODE//\//\\/}/" "$FILE" > "$FILE.tmp-sed"
        mv "$FILE.tmp-sed" "$FILE"
      done
      popd

      echo $VERSION > "$C9_DIR"/installed

      cd "$C9_DIR"
      DOWNLOAD https://raw.githubusercontent.com/c9/install/master/packages/license-notice.md "Third-Party Licensing Notices.md"

      echo ":Done. INSTALL"
      echo ""
    ;;

    "base" )
      echo "Installing base packages. Use --help for more options"
      start install node tmux_install nak ptyjs collab
    #   start install collab
      echo "DONE BASE"
      echo ""
    ;;

    * )
      start base
    ;;
  esac
  echo "INSTALL COMPLETE"
  echo ""
  echo ""
}

check_deps() {
  local ERR
  local OS

  if [[ `cat /etc/os-release 2>/dev/null` =~ CentOS ]]; then
    OS="CentOS"
  elif [[ `cat /proc/version 2>/dev/null` =~ Ubuntu|Debian ]]; then
    OS="DEBIAN"
  fi

  for DEP in make gcc; do
    if ! has $DEP; then
      echo "Error: please install $DEP to proceed" >&2
      if [ "$OS" == "CentOS" ]; then
        echo "To do so, log into your machine and type 'yum groupinstall -y development'" >&2
      elif [ "$OS" == "DEBIAN" ]; then
        echo "To do so, log into your machine and type 'sudo apt-get install build-essential'" >&2
      fi
      ERR=1
    fi
  done

  # CentOS
  if [ "$OS" == "CentOS" ]; then
    if ! yum list installed glibc-static >/dev/null 2>&1; then
      echo "Error: please install glibc-static to proceed" >&2
      echo "To do so, log into your machine and type 'yum install glibc-static'" >&2
      ERR=1
    fi
  fi

  check_python

  if [ "$ERR" ]; then exit 1; fi
}

check_python() {
  #if type -P python2.7 &> /dev/null; then
  #  PYTHONVERSION="2.7"
  #  PYTHON="python2.7"
  if type -P python &> /dev/null; then
    PYTHONVERSION=`python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))'`
    PYTHON="python3"
  fi

  #if [[ $PYTHONVERSION != "2.7" ]]; then
  #  echo "Python version 2.7 is required to install pty.js. Please install python 2.7 and try again. You can find more information on how to install Python in the docs: https://docs.c9.io/ssh_workspaces.html"
  #  exit 100
  #fi
}

# NodeJS

download_virtualenv() {
  VIRTUALENV_VERSION="virtualenv-20.0.21"
  DOWNLOAD "https://pypi.python.org/packages/source/v/virtualenv/$VIRTUALENV_VERSION.tar.gz" $VIRTUALENV_VERSION.tar.gz
  tar xzf $VIRTUALENV_VERSION.tar.gz
  rm $VIRTUALENV_VERSION.tar.gz
  mv $VIRTUALENV_VERSION virtualenv
}

ensure_local_gyp() {
  # when gyp is installed globally npm install pty.js won't work
  # to test this use `sudo apt-get install gyp`
  if [ `"$PYTHON" -c 'import gyp; print(gyp.__file__)' 2> /dev/null` ]; then
    echo "You have a global gyp installed. Setting up VirtualEnv without global pakages"
    rm -rf virtualenv
    rm -rf python
    if has virtualenv; then
      virtualenv -p python3 "$C9_DIR/python"
    else
      download_virtualenv
      "$PYTHON" virtualenv/virtualenv.py "$C9_DIR/python"
    fi
    if [[ -f "$C9_DIR/python/bin/python3" ]]; then
      PYTHON="$C9_DIR/python/bin/python3"
    else
      echo "Unable to setup virtualenv"
      exit 1
    fi
  fi
  "$YARN" config set python "$PYTHON" -g
  echo "PYTHON  $PYTHON"
  "$YARN" config set unsafe-perm true -g

  local GYP_PATH=$C9_DIR/node/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js
  if [ -f  "$GYP_PATH" ]; then
    ln -s "$GYP_PATH" "$C9_DIR"/node/bin/node-gyp &> /dev/null || :
  fi
}

node(){
  # clean up
  rm -rf node
  rm -rf node.tar.gz

  echo :Installing Node $NODE_VERSION

  DOWNLOAD https://nodejs.org/dist/"$NODE_VERSION/node-$NODE_VERSION-$1-$2.tar.gz" node.tar.gz
  tar xzf node.tar.gz
  mv "node-$NODE_VERSION-$1-$2" node
  rm -f node.tar.gz

  # use local npm cache
  "$NPM" config -g set cache  "$C9_DIR/tmp/.npm"
 # "$NPM" install --global yarn

  #rm package-lock.json
  #"$YARN" config set cache-folder "$C9_DIR/tmp/.yarn"
  ensure_local_gyp

}

compile_tmux(){
  cd "$C9_DIR"
  echo ":Compiling libevent..."
  tar xzf libevent-2.1.8-stable.tar.gz
  rm libevent-2.1.8-stable.tar.gz
  cd libevent-2.1.8-stable
  echo ":Configuring Libevent"
  ./configure --disable-shared --prefix="$C9_DIR/local"
  echo ":Compiling Libevent"
  make
  echo ":Installing libevent"
  make install

  cd "$C9_DIR"
  echo ":Compiling ncurses..."
  tar xzf ncurses-6.0.tar.gz
  rm ncurses-6.0.tar.gz
  cd ncurses-6.0
  echo ":Configuring Ncurses"
  CPPFLAGS=-P ./configure --prefix="$C9_DIR/local" --without-tests --without-cxx
  echo ":Compiling Ncurses"
  make
  echo ":Installing Ncurses"
  make install

  cd "$C9_DIR"
  echo ":Compiling tmux..."
  tar xzf tmux-3.1b.tar.gz
  rm tmux-3.1b.tar.gz
  cd tmux-3.1b
  echo ":Configuring Tmux"
  ./configure CFLAGS="-I$C9_DIR/local/include -I$C9_DIR/local/include/ncurses" LDFLAGS="-static-libgcc -L$C9_DIR/local/lib" --prefix="$C9_DIR/local"
  echo ":Compiling Tmux"
  make
  echo ":Installing Tmux"
  make install
}

tmux_download(){
  echo ":Downloading tmux source code"
  echo ":N.B: This will take a while. To speed this up install tmux 2.2 manually on your machine and restart this process."

  echo ":Downloading Libevent..."
  DOWNLOAD https://raw.githubusercontent.com/c9/install/master/packages/tmux/libevent-2.1.8-stable.tar.gz libevent-2.1.8-stable.tar.gz
  echo ":Downloading Ncurses..."
  DOWNLOAD https://github.com/c9/install/raw/master/packages/tmux/ncurses-6.0.tar.gz ncurses-6.0.tar.gz
  echo ":Downloading Tmux..."
  # DOWNLOAD https://raw.githubusercontent.com/c9/install/master/packages/tmux/tmux-1.9.tar.gz
  DOWNLOAD https://github.com/tmux/tmux/releases/download/3.1b/tmux-3.1b.tar.gz tmux-3.1b.tar.gz
}

check_tmux_version(){
  if [ ! -x "$1" ]; then
    return 1
  fi
  tmux_version=$($1 -V | sed -e's/^[a-z0-9.-]* //g' | sed -e's/[a-z]*$//')
  if [ ! "$tmux_version" ]; then
    return 1
  fi

  if [ "$("$PYTHON" -c "print(1.7<=$tmux_version and $tmux_version <= 3.1)")" == "True" ]; then
    return 0
  else
    return 1
  fi
}

tmux_install(){
  echo :Installing TMUX
  mkdir -p "$C9_DIR/bin"
  if check_tmux_version "$C9_DIR/bin/tmux"; then
    echo ':Existing tmux version is up-to-date'

  # If we can support tmux 1.9 or detect upgrades, the following would work:
  elif has "tmux" && check_tmux_version "$(which tmux)"; then
    echo ':A good version of tmux was found, creating a symlink'
    ln -sf "$(which tmux)" "$C9_DIR"/bin/tmux
    return 0

  # If tmux is not present or at the wrong version, we will install it
  else
    if [ $os = "darwin" ]; then
      if ! has "brew"; then
        # http://brew.sh/
        DOWNLOAD https://raw.githubusercontent.com/Homebrew/install/master/install installbrew
        ruby installbrew
      fi
      brew install tmux > /dev/null ||
        (brew remove tmux &>/dev/null && brew install tmux >/dev/null)
      ln -sf "$(which tmux)" "$C9_DIR"/bin/tmux
    # Linux
    else
      if ! has "make"; then
        echo ":Could not find make. Please install make and try again."
        exit 100;
      fi

      tmux_download
      compile_tmux
      ln -sf "$C9_DIR"/local/bin/tmux "$C9_DIR"/bin/tmux
    fi
  fi

  if ! check_tmux_version "$C9_DIR"/bin/tmux; then
    echo "Installed tmux does not appear to work:"
    exit 100
  fi
}

collab(){
  echo :Installing Collab Dependencies
  #"$YARN" cache verify
  "$YARN" add sqlite3@3.1.8
  "$YARN" add sequelize@2.0.0-beta.0
  mkdir -p "$C9_DIR"/lib
  cd "$C9_DIR"/lib
  DOWNLOAD https://raw.githubusercontent.com/c9/install/master/packages/sqlite3/linux/sqlite3.tar.gz sqlite3.tar.gz
  tar xzf sqlite3.tar.gz
  rm sqlite3.tar.gz
  ln -sf "$C9_DIR"/lib/sqlite3/sqlite3 "$C9_DIR"/bin/sqlite3
}

nak(){
  echo :Installing Nak
  echo `which yarn`
  echo `ls -l /root/.c9/node_modules/.bin`

  "$YARN" add https://github.com/astro-friedel/nak.git
  echo "DONE"
  echo `ls -l /root/.c9/node_modules/.bin`

}

ptyjs(){
  echo :Installing node-pty
  echo `ls -l /root/.c9/node_modules/.bin`

  "$YARN" add node-pty-prebuilt-multiarch@0.10.0

  if ! hasPty; then
    echo "Unknown exception installing node-pty"
   # "$C9_DIR/node/bin/node" -e "console.log(require('node-pty'))"
    "$C9_DIR/node/bin/node" -e "console.log(require('node-pty-prebuilt-multiarch'))"
    exit 100
  fi
}

hasPty() {
 # local HASPTY=$("$C9_DIR/node/bin/node" -p "typeof require('node-pty').createTerminal=='function'" 2> /dev/null)
  local HASPTY=$("$C9_DIR/node/bin/node" -p "typeof require('node-pty-prebuilt-multiarch').createTerminal=='function'" 2> /dev/null)
  if [ "$HASPTY" != true ]; then
    return 1
  fi
}

coffee(){
  echo :Installing Coffee Script
  "$YARN" add coffee
}

less(){
  echo :Installing Less
  "$YARN" add less
}

sass(){
  echo :Installing Sass
  "$YARN" add sass
}

typescript(){
  echo :Installing TypeScript
  "$YARN" add typescript
}

stylus(){
  echo :Installing Stylus
  "$YARN" add stylus
}

# go(){

# }

# heroku(){

# }

# rhc(){

# }

# gae(){

# }

start "$@"

# cleanup tmp files
rm -rf "$C9_DIR/tmp"