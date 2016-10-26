# $Id: COSas.spec,v 1.35 2016/09/18 08:13:31 jim Exp $
# (C) Nov 2010-May 2015 by Jim Klimov, JSC COS&HT
### NOTE/TODO: As an initial opensourcing code drop, this script exposes too
### many internals of the original development environment. Generalize it!
# RPM-build spec file for COSas package
# Copy it to the SPECS root of your RPM build area
# See Also: http://www.rpm.org/max-rpm/s1-rpm-build-creating-spec-file.html
### runs ok on buildhost as e.g.:
###   su - jim
###   cd rpm/BUILD
###   rpmbuild -bb COSas.spec
#
#
Summary: COS admin scripts
Name: COSas
Version: 1.9.34
Release: 1
License: "(C) 2004-2016 by Jim Klimov, JSC COS&HT, for support of COS projects"
Group: Utilities
#Group: Applications/System
#Source: https://github.com/cos-ht/COSas
URL: https://github.com/cos-ht/COSas
Distribution: RHEL/CentOS 5 Linux
Vendor: JSC COS&HT (Center of Open Systems and High Technologies, MIPT, www.cos.ru)
Packager: Jim Klimov <jimklimov@cos.ru>
Prefix: /opt/COSas
BuildRoot: /tmp/rpmbuild-COSas
Requires: /bin/bash, /bin/sh, /usr/bin/perl
# RHEL finds requirement for perl(MIME::Base64) in its perl; ALTLinux does not
AutoReqProv: no

%description
These scripts allow for monitoring system state, making backup dumps,
cleaning dump dirs, etc

%prep
#set
WORKDIR="$RPM_BUILD_DIR/$RPM_PACKAGE_NAME-$RPM_PACKAGE_VERSION-$RPM_PACKAGE_RELEASE"
[ x"$RPM_BUILD_ROOT" != x ] && WORKDIR="$RPM_BUILD_ROOT"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"/opt/COSas/etc
#mkdir -p "$WORKDIR"/etc
#ln -s ../opt/COSas/etc "$WORKDIR"/etc/COSas
mkdir -p "$WORKDIR"/opt/COSas/bin && \
    tar c -C /home/jim/cos/adminscripts/bin --exclude CVS -f - . | \
    tar x -C "$WORKDIR"/opt/COSas/bin -f -
mkdir -p "$WORKDIR"/opt/COSas/pkg && \
    tar c -C /home/jim/cos/adminscripts -f - COSas.spec | \
    tar x -C "$WORKDIR"/opt/COSas/pkg -f -
mkdir -p "$WORKDIR"/opt/COSas/pkg/COSas && \
    tar c -C /home/jim/cos/adminscripts -f - postinstall postremove | \
    tar x -C "$WORKDIR"/opt/COSas/pkg/COSas -f -
#mkdir "$WORKDIR" && \
#    cp -p /home/jim/cos/adminscripts/COSas.spec "$WORKDIR"
#mkdir "$WORKDIR"/bin && \
#    cp -p /home/jim/cos/adminscripts/bin/*.* "$WORKDIR"/bin

%files
%attr(-, bin, bin) %dir /opt/COSas
%attr(-, bin, bin) %dir /opt/COSas/bin
%attr(750, bin, bin) %dir /opt/COSas/etc
%attr(700, bin, bin) %dir /opt/COSas/pkg
%attr(700, bin, bin) %dir /opt/COSas/pkg/COSas
%attr(-, bin, bin) /opt/COSas/pkg/COSas.spec
%attr(-, bin, bin) /opt/COSas/pkg/COSas/postinstall
%attr(-, bin, bin) /opt/COSas/pkg/COSas/postremove
%attr(-, bin, bin) /opt/COSas/bin/agent-freespace-lfs.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-freespace.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-mail-pop3.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-mail-smtp.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-mail.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-ftp.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-ssh.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-mountpt.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-tcpip-grep.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-tcpip-perl.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-tcpip.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-web-amlogin.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-web-amloginHost.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-web-portal.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-web-portalOra.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-web-genericparser.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-web.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-web-openssologin.sh
%attr(-, bin, bin) /opt/COSas/bin/agent-web-openssologinHost.sh
%attr(-, bin, bin) /opt/COSas/bin/check-amserver-login.sh
%attr(-, bin, bin) /opt/COSas/bin/check-magnolia.sh
%attr(-, bin, bin) /opt/COSas/bin/check-portal-local.sh
%attr(-, bin, bin) /opt/COSas/bin/check-psam.sh
%attr(-, bin, bin) /opt/COSas/bin/clean-dump.sh
%attr(-, bin, bin) /opt/COSas/bin/clean-zfs-snaps.sh
%attr(-, bin, bin) /opt/COSas/bin/clonedir.sh
%attr(-, bin, bin) /opt/COSas/bin/compressor_choice.include
%attr(-, bin, bin) /opt/COSas/bin/compressor_list.include
%attr(-, bin, bin) /opt/COSas/bin/diag-runtime.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-generic.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-alfresco.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-magnolia.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-mfc.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-mio-all.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-mysql-export-multiple.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-mysql-export.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-named.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-oracle-export-actual.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-oracle-export-multiple.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-oracle-export.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-pgsql-export-multiple.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-pgsql-export.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-portal-all-7.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-portal-all.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-portal-config.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-portal-content.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-portal-mps.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sundsee6-ads-ldif.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sundsee6-ads.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sundsee6-dps1.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sundsee6-ldif.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sundsee6.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sundsee7-ldif.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sundsee7-agent.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sundsee7.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sunics5-archive.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sunics5-hotbackup.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sunisw.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sunmsg.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sunmsg-config.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-oucs-config.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sws7-config.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-syscfg-freebsd.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-syscfg-sol.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-syscfg-lin.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-syscfg.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-clamav.sh
%attr(-, bin, bin) /opt/COSas/bin/dumper-sendmailcfg.sh
%attr(-, bin, bin) /opt/COSas/bin/findcores.sh
%attr(-, bin, bin) /opt/COSas/bin/ldifsort-fulltree.pl
%attr(-, bin, bin) /opt/COSas/bin/ldifsort.pl
%attr(-, bin, bin) /opt/COSas/bin/logkeep-sendmail.sh
%attr(-, bin, bin) /opt/COSas/bin/logkeep-mail.sh
%attr(-, bin, bin) /opt/COSas/bin/logkeep-portal.sh
%attr(-, bin, bin) /opt/COSas/bin/logkeep-weblb.sh
%attr(-, bin, bin) /opt/COSas/bin/proctree.sh
%attr(-, bin, bin) /opt/COSas/bin/pkgdep.sh
%attr(-, bin, bin) /opt/COSas/bin/rsync-backups.sh
%attr(-, bin, bin) /opt/COSas/bin/rsync-loop.sh
%attr(-, bin, bin) /opt/COSas/bin/rsync-loop-init.sh
%attr(-, bin, bin) /opt/COSas/bin/rsync-zfshot.sh
%attr(-, bin, bin) /opt/COSas/bin/rsync-backup-toZFSsnapshots.sh
%attr(-, bin, bin) /opt/COSas/bin/runlevel_check.include
%attr(-, bin, bin) /opt/COSas/bin/sjsms-sunnumusers.sh
%attr(-, bin, bin) /opt/COSas/bin/test-archive.sh
%attr(-, bin, bin) /opt/COSas/bin/timerun.sh
%attr(-, bin, bin) /opt/COSas/bin/zfsacl-copy.sh
%attr(-, bin, bin) /opt/COSas/bin/zpool-scrub.sh

%postun
#set -x
### For buggy old RPMs
[ x"$RPM_INSTALL_PREFIX" = x ] && RPM_INSTALL_PREFIX="/opt/COSas"
### For included Solaris install scripts
BASEDIR="$RPM_INSTALL_PREFIX"
export BASEDIR
### Do some work...
[ -s "$RPM_INSTALL_PREFIX/pkg/COSas/postremove" ] && \
    . "$RPM_INSTALL_PREFIX/pkg/COSas/postremove"
[ -L /etc/COSas ] && rm -f /etc/COSas
true

%post
#set -x
### For buggy old RPMs
[ x"$RPM_INSTALL_PREFIX" = x ] && RPM_INSTALL_PREFIX="/opt/COSas"
### For included Solaris install scripts
BASEDIR="$RPM_INSTALL_PREFIX"
export BASEDIR
### Do some work...
_LINKTGT="`echo ../$RPM_INSTALL_PREFIX/etc | sed 's/\/\//\//g' 2>/dev/null`" || \
    _LINKTGT="../$RPM_INSTALL_PREFIX/etc"
[ ! -f /etc/COSas -a ! -L /etc/COSas -a ! -d /etc/COSas ] && \
    ln -s "$_LINKTGT" /etc/COSas
### Create typical config files like in Solaris postinstall script...
[ -s "$RPM_INSTALL_PREFIX/pkg/COSas/postinstall" ] && \
    . "$RPM_INSTALL_PREFIX/pkg/COSas/postinstall"
true
