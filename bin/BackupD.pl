#!/usr/bin/perl

###########################################################################
#
# $Id: BackupD.pl,v 1.11 2002/07/09 10:53:36 oliver Exp $
#
# $Log: BackupD.pl,v $
# Revision 1.11  2002/07/09 10:53:36  oliver
# I cleaned out some errors... I found them while distributing the new rpm...
#
# Revision 1.10  2002/07/09 10:34:48  oliver
# Added clean-up for rsync-backups and a lot of comments. The config was changed because of testing.
#
# Revision 1.9  2002/06/25 21:47:50  oliver
# Many small changes. Added autoflush, Added _usefull_ logging. Fixed some bugs. Corrected the .spec-File and the init-script.
#
# Revision 1.8  2002/06/25 14:45:20  oliver
# Moved it one level deeper. It's easier to make a tarball...
#
# Revision 1.7  2002/06/25 14:07:28  oliver
# We dont't need to import POSIX twice
#
# Revision 1.6  2002/06/25 14:06:15  oliver
# Some error with the cvs-id...
#
# Revision 1.5  2002/06/25 14:04:41  oliver
# Readded cvs history to BackupD and deleted Changes
#
# Revision 1.2  2002/06/25 11:28:10  oliver
# Added cvs-tags...
#
# Revision 1.2  2002/06/25 11:00:03  marcel
# cleaning up
#
# Revision 1.1  2002/06/25 10:56:26  marcel
# initial import
#
############################################################################
#
# BackupD - A Backup Daemon
# Copyright (c) Oliver Pitzeier, June 2002"
#               oliver@linux-kernel.at
#
# Changes are welcome, but please inform me about those!
#
# Contributions and code cleanups by Marcel Grünauer <m.gruenauer@chello.at>
#
############################################################################

use strict;
use warnings;
use IO::File;
use Time::localtime;
use Getopt::Long;
use POSIX qw(setsid);

# OK, here are some variables.
# $VERSION is changed after each commit to the CVS tree. Oh yes,
# we use CVS for better control of the commits by our authors.
# I'm the main author of this program.
my $PROGNAME   = 'BackupD.pl';
my $AUTHOR     = 'Oliver Pitzeier <oliver@linux-kernel.at>';
(our $VERSION) = '$Revision: 1.11 $' =~ /([\d.]+)/;

my $configfile = "BackupD.cfg";    # Configfile where we find what should be backuped.
my $backupdir  = "/backup";        # Please do not add a slash (or even more) at the end
my $interval   = 60;               # Once per minute
my $help;
my $daemon;
my $testrun;

my $datetime = sprintf("%04d-%02d-%02d+%02d_%02d_%02d",
    localtime->year+1900, localtime->mon+1, localtime->mday,
    localtime->hour, localtime->min, localtime->sec);
my $now_hour   = localtime->hour;
my $now_minute = localtime->min;

# Get the options using Getopt::Long. More information see: "perldoc Getopt::Long"
my $result = GetOptions(
    "interval|n=i" => \$interval,
    "help|?|h"     => \$help,
    "daemon|D|d"   => \$daemon,
    "file|F|f=s"   => \$configfile,
    "configtest"   => sub { print_config() },
    "test|T|t"     => \$testrun,
);

print "TEST RUN!\n" if $testrun;

if ($help) {
    # Print the help - hard to guess, isn't it... :o)
    print "$PROGNAME - by $AUTHOR\n\n";
    print "usage: $PROGNAME [--interval|-n <seconds>] [--daemon|-d|-D] [--help|-h|-?]\n";
    print "--interval|-n :      This option defaults to: $interval seconds\n";
    print "--daemon|-d|-D:      This options switch the programm to deamon mode. Default: off\n";
    print "--file|-f|-F  :      Path to config file. Default: BackupD.cfg\n";
    print "--configtest  :      Reads and prints config file, then exits.\n";
    print "--test|-t|-T  :      Test run; prints commands but won't execute them. Default: off\n";
    print "--help|-h|-?  :      I guess you already know it, if you read this here! :o)\n";
    exit 0
}

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

sub print_config {                 # Print the configfile
    # This functions only prints the config an a readable way
    # So the sysadmin or someone else can check if the config
    # file is read and interpreted correctly
    my @config = read_config($configfile);
    use Data::Dumper;
    print Dumper \@config;
    exit 0;
}

sub find_psql_databases($$) {       # Find all psql-databases on a host
   # Define some variables
   my $host        = shift;
   my $extraparams = shift || '';

   my @dbs;
   my $command = "LC_ALL=en_US psql -h $host $extraparams -l";

   # Execute psql (see $command above) and pipe it. We then can
   # use the output just as if it would be a normal filehandler
   open my $fh, "$command |" or die "can't pipe from '$command': $!\n";

   my $seen_divider;
   # Jump over the headers. I hope the header looks the same
   # for different PostgreSQL versions. This was written and
   # tested with PostgreSQL 7.2(.1)
   while (<$fh>) {
   	chomp;
	if (/^[-+]+$/) {
		$seen_divider++;
		next;
	}
   	next unless $seen_divider;
	next unless /\|/;
	my ($db) = (split);
	push @dbs => $db unless $db =~ /template[01]/;
   }
   close $fh or die "can't close pipe: $!\n";

   # Return an array of database-names
   return @dbs;
}

sub rsync_backup_pre($$) {          # Run rsync-backup for given host
    # Define some variables
    my ($host, $what) = @_;
    my $dir = "$backupdir/$host/rsync/$what";
    $_ = $dir;
    ($dir) = (m{(.*)/(?!$)}) if ($what =~ /\//);
    (my $logname = $what) =~ s!/!_!g;

    # Create the backupdir of the current host and print some message
    return unless assert_dir("$backupdir/$host/rsync/$what");
    print "Running rsync-backup for \"$host\:\:$what\".\n";

    # Cleanup of old rsync backups
    # This runs trough the whole backup-tree this means that every
    # host backups will be cleaned up and not only the current host
    # I whish the were more documentation like this. :o)

    print "Running cleanup...\n";

    # This part gets the date in a way we can use it for calculating
    my $currentdate = sprintf("%04d%02d%02d", localtime->year+1900, localtime->mon+1, localtime->mday);

    # A very silly name for a variable. oldnes describes what _old_ is. :o)
    # Seven days (one week) is old. This is not really true if a new month
    # just began. Let me know if you want to write a better routine for this.
    # It's just a quick hack.
    my $oldnes = 7;
    $oldnes = 77 if localtime->mday < 7;

    # Find all compress tarballs. Maybe there will be file from the rsync as
    # well... But this is a quick hack as well.
    my $command=qq!find $backupdir -name *.tgz* -maxdepth 2 -printf "%TY%Tm%Td %p\n"!;
    open my $fh, "$command |" or die "can't pipe '$command': $!\n";

    # Get the filenames and the date, split it and delete the file if it is
    # older than the allowed "oldnes". Yeah here again the crazy variable.
    while (<$fh>) {
        my ($date, $filename) = split(" ");
        my $difference = $currentdate - $date;
        print "$filename is old!\n"  if $difference >= $oldnes;
        do_system("rm -f $filename") if $difference >= $oldnes;
    }
    close $fh;
    # End of cleanup routine

    do_system(<<EOCMD);
rsync -avz $host\:\:$what $dir \\
    >$backupdir/$host/last-rsync-$logname.log 2>&1 && \\
tar cfvz $backupdir/$host/$logname-$datetime.tgz $dir/* \\
    >$backupdir/$host/last-rsync-tar-$logname.log 2>&1 &
EOCMD
}

sub psql_backup_pre($$$) {          # Run psql-backup for given host
    # Define some variables
    my ($host, $what, $extraparams) = @_;

    # Create the psql-backupdir with the current timestamp
    return unless assert_dir("$backupdir/$host/psql/$datetime");

    # For each db in the array (returned from find_psql_databases) make
    # a backup. If the dbname in the config is "all" then _all_ databases will be
    # backuped.
    for my $dbname ($what eq 'all' ? find_psql_databases($host, $extraparams) : $what) {
	print qq!Running psql-backup for "$host\:\:$dbname" with extraparams: $extraparams\n!;
	do_system(<<EOCMD, "for db: $dbname");
pg_dump -h $host $extraparams $dbname | \\
    gzip -c > $backupdir/$host/psql/$datetime/$dbname.psql.gz \\
    2> $backupdir/$host/last-psql-$dbname.log &
EOCMD
    }
}

sub assert_dir {
    # This creates a host and/or backup-type specific backup-dir and
    # has some kind of error catching. There is no more to say.
    my $dir = shift;
    return 1 if -d $dir;
    print "Hostdir doesn't exist\nI'll create it for you...\n";
    do_system("mkdir -p $dir");
    return 1 if -d $dir || $testrun;
    print "Cannot create it... I wanted to, but it still doesn't exist.\n";
    return 0;
}

sub do_system {
    # This function executes a systemcall and checks if an error occured.
    my ($command, $msg) = @_;
    $msg ||= '';
    if ($testrun) {
        print "TEST: $command\n";
    } else {
        system($command);
        print $? ? "Error occured: $?\n" : "Everything seems to be done$msg!\n";
    }
}

sub main_loop {
    # This is the main program loop.
    # It is executed from the memory resistent (daemon like) part
    # of this program
    print "Reading config...\n";
    for my $conf (read_config($configfile)) {
        # Check if it is time to backup and what kind it is.
        # This is allready a new thread of BackupD 
        if ($conf->{backup_type} eq 'psql')  {
                if($now_hour == $conf->{hour} && $now_minute == $conf->{minute}) {
                psql_backup_pre($conf->{host}, $conf->{what}, $conf->{extraparams} || '');
                }
        } elsif ($conf->{backup_type} eq 'rsync') {
                if($now_hour == $conf->{hour} && $now_minute == $conf->{minute}) {
	        rsync_backup_pre($conf->{host}, $conf->{what});
                }
        # I hope someone adds more backup-types :o)
        } else {
	    print "I really don't know how to handle THIS!\n"
        }
    }
}

if($daemon) {
    # If this should be a daemon set stdout and stderr to the logfile, set the autoflush flag
    # and fork a kind
    open STDOUT, '>>/var/log/BackupD.log' or die "Can't write to /var/log/BackupD.log: $!";
    open STDERR, '>>/var/log/BackupD.log' or die "Can't write to /var/log/BackupD.log: $!";
    autoflush STDOUT 1;
    autoflush STDERR 1;

    defined(my $pid = fork)    or die "Can't fork: $!\n";
    exit if $pid;
    setsid                     or die "Can't start a new session: $!\n";

    print "Starting daemon mode... Looping now...\n";
    while(1) {
        $datetime = sprintf("%04d-%02d-%02d+%02d_%02d_%02d",
            localtime->year+1900, localtime->mon+1, localtime->mday,
            localtime->hour, localtime->min, localtime->sec);

        my $log_datetime = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
            localtime->year+1900, localtime->mon+1, localtime->mday,
            localtime->hour, localtime->min, localtime->sec);
        $now_hour   = localtime->hour;
        $now_minute = localtime->min;

        # Print something to the logfile. This is called a checkpoint
        # Because then you can check after some failure, where it stopped.
        print "$log_datetime BackupD checkpoint - before backup\n";
        &main_loop;
        print "$log_datetime BackupD checkpoint - after backup\n";
        sleep $interval;
    }
} else {
    &main_loop;
}

=head1 NAME
BackupD - A Backup Daemon

=head1 SYNOPSYS

See BackupD --help

=head1 Example

    BackupD -d -n 60

=head1 DESCRIPTION

A perl-script/daemon that makes backups - what else have you expected?
 
This script can not be optained until it's out of development. :o)
Afterwards it will be available at linux-kernel.at and uptime.at

=head1 LICENSE

This program has been developed under GPL.

=head1 AUTHOR

Oliver Pitzeier <oliver@linux-kernel.at>
