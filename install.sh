#!/bin/bash
#
# Browser Exploitation Framework (BeEF) - Termux Automated Installer
# Adapted for Android / Termux environment

set -euo pipefail
NORMIFS=$IFS
SCRIFS=$'\n\t'
IFS=$SCRIFS

info() { echo -e "\\033[1;36m[INFO]\\033[0m  $*"; }
warn() { echo -e "\\033[1;33m[WARNING]\\033[0m  $*"; }
fatal() {
	echo -e "\\033[1;31m[FATAL]\\033[0m  $*"
	exit 1
}

command_exists() {
	command -v "${1}" >/dev/null 2>&1
}

is_termux() {
	if [ -n "${TERMUX_VERSION:-}" ]; then
		return 0
	fi
	if [ -n "${TERMUX_APP_PID:-}" ]; then
		return 0
	fi
	case "${PREFIX:-}" in
		*com.termux*) return 0 ;;
	esac
	return 1
}

banner() {
	echo
	echo -e "\\033[1;31m██████╗ ███████╗███████╗███████╗   ██╗  ██╗███████╗███████╗\\033[0m"
	echo -e "\\033[1;31m██╔══██╗██╔════╝██╔════╝██╔════╝   ╚██╗██╔╝██╔════╝██╔════╝\\033[0m"
	echo -e "\\033[1;33m██████╔╝█████╗  █████╗  █████╗      ╚███╔╝ ███████╗███████╗\\033[0m"
	echo -e "\\033[1;33m██╔══██╗██╔══╝  ██╔══╝  ██╔══╝      ██╔██╗ ╚════██║╚════██║\\033[0m"
	echo -e "\\033[1;36m██████╔╝███████╗██║     ██║        ██╔╝ ██╗███████║███████║\\033[0m"
	echo -e "\\033[1;36m╚═════╝ ╚══════╝╚═╝     ╚═╝        ╚═╝  ╚═╝╚══════╝╚══════╝\\033[0m"
	echo
	echo -e "        \033[0;36mI N S T A L L E R   ·   T E R M U X   E D I T I O N\033[0m"
	echo -e "                 \033[0;90mt.me/cybe4\033[0m"
	echo
	echo "#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#"
	echo;sleep 1.5
}

ask() {
	local prompt="$1"
	local reply=''
	if [ -r /dev/tty ]; then
		read -rp "${prompt}" reply < /dev/tty || reply=''
	else
		read -rp "${prompt}" reply || reply=''
	fi
	echo "${reply}"
}

get_permission() {
	warn 'This script will clone BeEF and install all required dependencies for Termux.'
	warn 'Expect a long build and roughly 1.5 GB of free space.'

	local answer
	answer=$(ask "Are you sure you wish to continue (Y/n)? ")
	if [ "$(echo "${answer}" | tr "[:upper:]" "[:lower:]")" = "n" ]; then
		fatal 'Installation aborted'
	fi
}

get_free_kb() {
	local target flags out
	for target in "${PREFIX:-}" "${HOME:-}" "."; do
		[ -n "${target}" ] || continue
		[ -d "${target}" ] || continue
		for flags in '-Pk' '-k' ''; do
			out=$(df ${flags} "${target}" 2>/dev/null | awk 'NR==2 {print $4; exit}') || continue
			case "${out}" in
				'' | *[!0-9]*) continue ;;
			esac
			echo "${out}"
			return 0
		done
	done
	return 1
}

check_disk_space() {
	info 'Checking free disk space...'
	local free_space
	if ! free_space=$(get_free_kb); then
		warn 'Could not determine free disk space - continuing anyway.'
		return 0
	fi

	local min_space=1572864 # ~1.5 GB in KB
	if [ "${free_space}" -ge "${min_space}" ]; then
		info 'Enough free disk space verified.'
		return 0
	fi

	warn "Low free space detected ($((free_space / 1024)) MB available, ~1536 MB recommended)."
	local answer
	answer=$(ask "Run a package manager cache cleanup to free space (Y/n)? ")
	if [ "$(echo "${answer}" | tr "[:upper:]" "[:lower:]")" = "n" ]; then
		warn 'Continuing without cleanup.'
		return 0
	fi

	info 'Cleaning the Termux package cache...'
	pkg clean || apt-get clean || true
	info 'Cleanup finished.'
}

check_termux() {
	info 'Detecting environment...'
	if ! is_termux; then
		fatal 'This installer only supports Termux on Android.'
	fi

	: "${PREFIX:=/data/data/com.termux/files/usr}"
	export PREFIX

	if [ ! -d "${PREFIX}" ]; then
		fatal "Termux prefix not found at ${PREFIX}"
	fi

	info "Termux prefix: ${PREFIX}"
	info "Architecture: $(uname -m)"
}

clone_beef() {
	if [ -d "beef" ]; then
		info "Diretório 'beef' já existe. A atualizar repositório..."
		cd beef
		git pull origin master || true
		cd ..
	else
		info "A clonar o repositório oficial do BeEF..."
		git clone https://github.com/beefproject/beef.git
	fi
}

install_termux_deps() {
	info 'Keeping the device awake during the build (termux-wake-lock)...'
	command_exists termux-wake-lock && termux-wake-lock || warn 'termux-wake-lock unavailable'

	info 'Refreshing package index...'
	pkg update -y || warn 'pkg update reported errors'

	info 'Installing toolchain and dependencies (with automatic -y)...'
	pkg install -y build-essential || true

	pkg install -y \
		clang make pkg-config binutils \
		git curl wget ca-certificates \
		openssl openssl-tool \
		autoconf automake libtool bison patch \
		readline zlib libyaml libffi bzip2 xz-utils \
		sqlite libxml2 libxslt libcurl libiconv libgcrypt \
		ncurses python3 ruby

	if ! command_exists node; then
		pkg install -y nodejs || pkg install -y nodejs-lts || warn 'Could not install Node.js'
	fi

	pkg install -y espeak || true
	pkg install -y termux-api || true
}

termux_build_env() {
	: "${PREFIX:=/data/data/com.termux/files/usr}"
	info "Preparing build environment (PREFIX=${PREFIX})..."

	local missing=0
	for hdr in \
		"${PREFIX}/include/libxml2/libxml/parser.h" \
		"${PREFIX}/include/libxslt/xslt.h"; do
		if [ ! -f "${hdr}" ]; then
			missing=1
		fi
	done

	if [ "${missing}" -eq 1 ]; then
		warn 'Reinstalling missing xml/xslt headers...'
		pkg install -y libxml2 libxslt || true
	fi

	export CFLAGS="-I${PREFIX}/include -I${PREFIX}/include/libxml2 ${CFLAGS:-}"
	export CPPFLAGS="-I${PREFIX}/include -I${PREFIX}/include/libxml2 ${CPPFLAGS:-}"
	export CXXFLAGS="-I${PREFIX}/include -I${PREFIX}/include/libxml2 ${CXXFLAGS:-}"
	export LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}"
	export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
	export PATH="${PREFIX}/bin:${PATH}"

	export BUNDLE_JOBS=1
	export MAKEFLAGS='-j1'
	export EXECJS_RUNTIME=Node

	export BUNDLE_BUILD__NOKOGIRI="--use-system-libraries --with-xml2-dir=${PREFIX} --with-xslt-dir=${PREFIX}"
	export BUNDLE_BUILD__FFI="--with-ffi-dir=${PREFIX}"
	export BUNDLE_BUILD__SQLITE3="--enable-system-libraries"
}

install_beef_gems() {
	cd beef
	echo "Installing required Ruby gems..."

	if [ -w Gemfile.lock ]; then
		/bin/rm -f Gemfile.lock
	fi

	termux_build_env

	if ! command_exists bundle; then
		gem install bundler --no-document
	fi

	bundle config set --local build.nokogiri "--use-system-libraries --with-xml2-dir=${PREFIX} --with-xslt-dir=${PREFIX}" || true
	bundle config set --local build.ffi "--with-ffi-dir=${PREFIX}" || true
	bundle config set --local build.sqlite3 "--enable-system-libraries" || true
	bundle config set --local build.libv8-node "--with-system-v8" || true
	bundle config set --local jobs 1 || true
	bundle install --jobs 1

	if [ -f "config.yaml" ]; then
		info "Configurando credenciais padrão no config.yaml..."
		awk '
    /user:/ { sub(/"[^"]*"/, "\"cyber\""); }
    /passwd:/ { sub(/"[^"]*"/, "\"test\""); }
    { print }
' config.yaml > config.yaml.tmp && mv config.yaml.tmp config.yaml

	fi

	cd ..
}

finish() {
	echo
	echo "#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#"
	info "Install completed successfully!"
	echo
	info "Credenciais configuradas automaticamente:"
	info "  Utilizador: cyber"
	info "  Password:   test"
	echo
	info "Para iniciar o BeEF:"
	echo "  cd beef"
	echo "  ./beef"
	echo
	info "Para alterar as credenciais localmente, edite o ficheiro:"
	echo "  beef/config.yaml"
	echo
	info "Telegram de suporte: t.me/cybe4"
	echo "#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#"
	echo
}

main() {
	clear
	banner
	check_termux
	if [ -n "${GITACTIONS:-}" ]; then
		info 'Skipping prompts: running on Github Actions'
	else
		get_permission
		check_disk_space
	fi
	clone_beef
	install_termux_deps
	install_beef_gems
	finish
}

main "$@"
