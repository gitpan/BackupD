Summary: BackupD - A BackupD Daemon
Name: BackupD
Version: 1.0
Release: 1
License: GPL
Group: System Environment/Daemons
Source: http://linux-kernel.at/downloads/BackupD-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-root
Prereq: /sbin/chkconfig
Requires: perl >= 5.6.0

%description
BackupD is a perl-script/daemon that makes backups. It's configure
via a simple config-file.

%prep
%setup -q

%install

mkdir -p $RPM_BUILD_ROOT/etc/rc.d/init.d
mkdir -p $RPM_BUILD_ROOT/usr/sbin
mkdir -p $RPM_BUILD_ROOT/var/log

install -m 755 bin/BackupD.pl $RPM_BUILD_ROOT/usr/sbin/BackupD
install -m 644 etc/config.sbp.cfg $RPM_BUILD_ROOT/etc/BackupD.conf
install -m 755 BackupD.rc $RPM_BUILD_ROOT/etc/rc.d/init.d/BackupD

touch $RPM_BUILD_ROOT/var/log/BackupD.log

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%attr(750,root,root) /usr/sbin/BackupD
%config(noreplace) /etc/BackupD.conf
%config /etc/rc.d/init.d/BackupD
/var/log/BackupD.log
%doc README

%post
/sbin/chkconfig --add BackupD

%preun
if [ $1 = 0 ]; then
    service BackupD stop > /dev/null 2>&1
    /sbin/chkconfig --del BackupD
fi

%postun
if [ "$1" -eq "1" ]; then
    service squid condrestart >/dev/null 2>&1
fi

%changelog
* Tue Jun 25 2002 Oliver Pitzeier <oliver@linux-kernel.at>
- Inital .spec-File
