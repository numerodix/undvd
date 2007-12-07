Summary: Simple dvd ripping command line app
Name: undvd
Version: 9999
Release: 1
Copyright: GPL
Group: Applications/Multimedia
Source: http://www.opendesktop.org/content/download.php?content=64833&id=1&tan=78972573
#Patch: eject-2.0.2-buildroot.patch
BuildRoot: /var/tmp/%{name}-buildroot

%description
undvd is dvd ripping made *simple* with an easy interface to mencoder with
sensible default settings that give good results. For those times you just
want to rip a movie and not consider thousands of variables.

%prep
%setup -q

%build
make RPM_OPT_FLAGS="$RPM_OPT_FLAGS"

%install
make DESTDIR="$RPM_BUILD_ROOT" install

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%doc userguide.html

/usr/share/undvd/lib.sh
/usr/share/undvd/undvd.sh
/usr/share/undvd/dumptrack.sh
/usr/share/undvd/userguide.html
/usr/share/undvd/scandvd.sh
/usr/bin/undvd.sh
/usr/bin/scandvd.sh

%changelog
* Sun Mar 21 1999 Cristian Gafton <gafton@redhat.com> 
- auto rebuild in the new build environment (release 3)

* Wed Feb 24 1999 Preston Brown <pbrown@redhat.com> 
- Injected new description and group.
