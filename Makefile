SHARED=${DESTDIR}/usr/share/undvd
BIN=${DESTDIR}/usr/bin

all:
	-@true

install:
	mkdir -p ${SHARED}
	install -m644 lib.sh ${SHARED}
	install -m755 dumptrack.sh ${SHARED}
	install -m755 scandvd.sh ${SHARED}
	install -m755 undvd.sh ${SHARED}
	install -m644 userguide.html ${SHARED}

	mkdir -p ${BIN}
	ln -s ${SHARED}/scandvd.sh ${BIN}
	ln -s ${SHARED}/undvd.sh ${BIN}
