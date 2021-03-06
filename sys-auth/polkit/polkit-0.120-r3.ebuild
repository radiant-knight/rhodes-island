# Copyright 1999-2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit meson pam pax-utils systemd xdg-utils

DESCRIPTION="Policy framework for controlling privileges for system-wide services"
HOMEPAGE="https://www.freedesktop.org/wiki/Software/polkit https://gitlab.freedesktop.org/polkit/polkit"
SRC_URI="
	https://www.freedesktop.org/software/${PN}/releases/${P}.tar.gz
	https://github.com/ferion11/danrepo/releases/download/polkit_patchs/polkit-${PV}-duktape.patch.gz
"

LICENSE="LGPL-2"
SLOT="0"
KEYWORDS="~amd64"
IUSE="duktape examples gtk +introspection kde pam selinux systemd test"
#RESTRICT="!test? ( test )"
# Tests currently don't work with meson. See
#   https://gitlab.freedesktop.org/polkit/polkit/-/issues/144
RESTRICT="test"

BDEPEND="
	acct-user/polkitd
	acct-group/polkitd
	app-text/docbook-xml-dtd:4.1.2
	app-text/docbook-xsl-stylesheets
	dev-libs/glib
	dev-libs/gobject-introspection-common
	dev-libs/libxslt
	dev-util/glib-utils
	sys-devel/gettext
	virtual/pkgconfig
	introspection? ( dev-libs/gobject-introspection )
"
DEPEND="
	!duktape? ( dev-lang/spidermonkey:78[-debug] )
	duktape? ( dev-lang/duktape )
	dev-libs/glib:2
	dev-libs/expat
	pam? (
		sys-auth/pambase
		sys-libs/pam
	)
	!pam? ( virtual/libcrypt:= )
	systemd? ( sys-apps/systemd:0=[policykit] )
	!systemd? ( sys-auth/elogind )
"
RDEPEND="${DEPEND}
	acct-user/polkitd
	selinux? ( sec-policy/selinux-policykit )
"
PDEPEND="
	gtk? ( || (
		>=gnome-extra/polkit-gnome-0.105
		>=lxde-base/lxsession-0.5.2
	) )
	kde? ( kde-plasma/polkit-kde-agent )
"

DOCS=( docs/TODO HACKING NEWS README )

QA_MULTILIB_PATHS="
	usr/lib/polkit-1/polkit-agent-helper-1
	usr/lib/polkit-1/polkitd"

#PATCHES=(
#	#https://bugs.gentoo.org/698910
#	"${FILESDIR}"/polkit-0.120-duktape.patch
#)

src_prepare() {
	if use duktape ; then
		PATCHES+=(
			#from https://gitlab.freedesktop.org/polkit/polkit/merge_requests/35
			"${WORKDIR}"/polkit-${PV}-duktape.patch
		)
	fi

	default

	sed -i -e 's|unix-group:wheel|unix-user:0|' src/polkitbackend/*-default.rules || die #401513
}

src_configure() {
	xdg_environment_reset

	local emesonargs=(
		--localstatedir="${EPREFIX}"/var
		-Dauthfw="$(usex pam pam shadow)"
		-Dexamples=false
		-Dgtk_doc=false
		-Dman=true
		-Dos_type=gentoo
		-Dsession_tracking="$(usex systemd libsystemd-login libelogind)"
		-Dsystemdsystemunitdir="$(systemd_get_systemunitdir)"
		$(meson_use introspection)
		$(meson_use test tests)
		$(usex pam "-Dpam_module_dir=$(getpam_mod_dir)" '')
	)

	if use duktape ; then
		emesonargs+=(
			-Djs_engine=duktape
		)
	fi

	meson_src_configure
}

src_compile() {
	meson_src_compile

	# Required for polkitd on hardened/PaX due to spidermonkey's JIT
	pax-mark mr src/polkitbackend/.libs/polkitd test/polkitbackend/.libs/polkitbackendjsauthoritytest
}

src_install() {
	meson_src_install

	if use examples ; then
		docinto examples
		dodoc src/examples/{*.c,*.policy*}
	fi

	diropts -m 0700 -o polkitd
	keepdir /usr/share/polkit-1/rules.d

	# meson does not install required files with SUID bit. See
	#  https://bugs.gentoo.org/816393
	# Remove the following lines once this has been fixed by upstream
	fperms u+s /usr/bin/pkexec
	fperms u+s /usr/lib/polkit-1/polkit-agent-helper-1
}

pkg_postinst() {
	chmod 0700 "${EROOT}"/{etc,usr/share}/polkit-1/rules.d
	chown polkitd "${EROOT}"/{etc,usr/share}/polkit-1/rules.d
}
