SHARED=/usr/share/undvd
DOC=/usr/share/doc/undvd
BIN=/usr/bin

SHARED_CHROOT=${DESTDIR}${SHARED}
DOC_CHROOT=${DESTDIR}${DOC}
BIN_CHROOT=${DESTDIR}${BIN}

all: clean

clean:
	-@true

install:
	mkdir -p ${SHARED_CHROOT}
	install -m644 lib.sh ${SHARED_CHROOT}
	install -m755 scandvd.sh ${SHARED_CHROOT}
	install -m755 undvd.sh ${SHARED_CHROOT}
	install -m644 userguide.html ${DOC_CHROOT}

	mkdir -p ${BIN_CHROOT}
	ln -s ${SHARED}/scandvd.sh ${BIN_CHROOT}
	ln -s ${SHARED}/undvd.sh ${BIN_CHROOT}
