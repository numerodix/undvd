Summary: <description>
Name: <name>
Version: <version>
Release: <release>
License: <license>
Group: <license>
BuildArch: <arch>
Source: <source_url>
BuildRoot: /var/tmp/%{name}-buildroot
Requires: <deps>

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
/usr/share/undvd/scandvd.sh
/usr/bin/undvd.sh
/usr/bin/scandvd.sh

%changelog
