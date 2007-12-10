# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

inherit eutils

DESCRIPTION="<desc>"
HOMEPAGE="<homepage>"
SRC_URI="<tarball>"

LICENSE="<license>"
SLOT="0"
KEYWORDS="~x86"
IUSE="css xvid"

DEPEND="app-shells/bash
	sys-apps/gawk
	sys-apps/coreutils
	media-video/lsdvd
	media-video/mplayer
	css? ( media-libs/libdvdcss )"
RDEPEND="${DEPEND}"


pkg_setup() {
	einfo "Checking mplayer for USE flags we need..."
	for f in "encode dvd x264 mad"; do
		if ! built_with_use media-video/mplayer $f; then
			eerror "$f"
			die "mplayer merged without $f USE flag"
		fi
	done

	if use xvid; then
		if ! built_with_use media-video/mplayer xvid; then
			eerror "xvid missing. This means you cannot encode to xvid."
			die "mplayer merged without xvid USE flag"
		fi
	fi

	einfo "everything seems to be in order"
}

src_unpack() {
	unpack ${A}
	cd ${WORKDIR}
}

src_install() {
	emake DESTDIR="${D}" install || die "Install failed"
}
