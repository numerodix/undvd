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
IUSE="aac css ffmpeg matroska mp4 ogm xvid"

DEPEND="sys-apps/coreutils
	>=dev-lang/perl-5.8.8
	media-video/lsdvd
	media-video/mplayer
	css? (
		media-libs/libdvdcss
		media-video/vobcopy
	)
	ffmpeg? (
		media-video/ffmpeg
	)
	matroska? (
		media-video/mkvtoolnix
	)
	mp4? (
		media-video/mpeg4ip
	)
	ogm? (
		media-sound/ogmtools
	)"
RDEPEND="${DEPEND}"


pkg_setup() {
	einfo "Checking mplayer for USE flags we need..."
	mplayer_flags="encode dvd x264 mp3"
	for f in $mplayer_flags; do
		if ! built_with_use media-video/mplayer $f; then
			missing_flags="$f"
			eerror "$f missing"
		fi
	done

	if [ "$missing_flags" ]; then
		eerror
		eerror "Please re-emerge media-video/mplayer with USE=\"$mplayer_flags\""
		die "mplayer missing necessary USE flags"
	fi


	if use aac; then
		if ! built_with_use media-video/mplayer aac; then
			eerror
			eerror "aac missing. This means you cannot encode to aac."
			eerror "Please re-emerge media-video/mplayer with USE=\"aac\""
			die "mplayer merged without aac USE flag"
		fi
	fi

	if use xvid; then
		if ! built_with_use media-video/mplayer xvid; then
			eerror
			eerror "xvid missing. This means you cannot encode to xvid."
			eerror "Please re-emerge media-video/mplayer with USE=\"xvid\""
			die "mplayer merged without xvid USE flag"
		fi
	fi

	einfo " everything seems to be in order"
}

src_unpack() {
	unpack ${A}
	cd "${WORKDIR}"
}

src_install() {
	emake DESTDIR="${D}" install || die "Install failed"
}
