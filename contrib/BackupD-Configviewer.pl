#!/usr/bin/perl

use strict;
use warnings;
use CGI qw/:standard/;
use IO::File;

my $configfile = "/etc/BackupD.conf";

sub read_config($) {               # Read the configfile
    # Reads the config file and return it as an array.
    my $filename = shift;
    my $fh = new IO::File;
    my @config;
    die "couldn't open $filename" unless $fh->open("< $filename");
    while (<$fh>) {
        next if /^#/;
        chomp;
        my %data;
        @data{ qw/host backup_type what hour minute extraparams/ } = split(':');
        push @config => \%data;
    }
    close $fh;
    return @config;
}

print header;
print start_html(-title=>'BackupD Configuration Overview',
                 -author=>'oliver@linux-kernel.at',
                 -base=>'true',
                 -target=>'_blank',
                 -meta=>{'keywords'=>'BackupD configuration overview webinterface',
                         'copyright'=>'Copyright 2002 Oliver Pitzeier'},
                 -BGCOLOR=>'#0399FD');

print "<center><table border=1 width=60%>";
print "<tr><th>Hostname</th><th>Time</th><th>Backup Type</th><th>what to backup</th></tr>";

for my $conf (read_config($configfile)) {
    print "<tr>
           <td align=center>$conf->{host}</td>
           <td align=center>$conf->{hour}:$conf->{minute}</td>
           <td align=center>$conf->{backup_type}</td>
           <td>$conf->{what}</td>
           </tr>";
}
print "</center></table>";

print end_html;
