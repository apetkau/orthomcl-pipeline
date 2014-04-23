#!/usr/bin/env perl
# setup_database.pl
# Purpose: used to check for and setup a configuration file for
# the OrthoMCL database connection.

use warnings;
use strict;

use FindBin;
use DBI;
use DBD::mysql;
use File::Basename;
use Getopt::Long;

my $script_dir = $FindBin::Bin;

my $default_config = "$script_dir/../etc/orthomcl.config.example";

my $usage = "Usage: ".basename($0)." --user [user] --password [password] --host [host] --database [database]\n".
"Checks for a database connection and generates an orthomcl config file with the given parameters\n";

my ($user,$password,$host, $database);
if (not GetOptions(
	'user=s' => \$user,
	'password=s' => \$password,
	'host=s' => \$host,
	'database=s' => \$database))
{
	die "$!\n".$usage;
}

if (not (defined $user and
	 defined $password and
	 defined $host and
	 defined $database))
{
	die "missing database information\n".$usage;
}

my $parameters = parse_config($default_config);

print STDERR "Connecting to database $database on host $host with user $user ...";
my $db_connect_string = "dbi:mysql:$database:$host:mysql_local_infile=1";
my $dbh = DBI->connect($db_connect_string,$user,$password, {RaiseError => 1, AutoCommit => 0});
if (not defined $dbh)
{
	die "error connecting to database";
}
else
{
	print STDERR "OK\n";
}

$parameters->{'dbConnectString'} = $db_connect_string;
$parameters->{'dbLogin'} = $user;
$parameters->{'dbPassword'} = $password;

write_config($parameters);

sub write_config
{
	my ($parameters) = @_;

	foreach my $key (sort {$a cmp $b} keys %$parameters)
	{
		my $value = $parameters->{$key};
		print "$key=$value\n";
	}
}

sub parse_config
{
	my ($config_file) = @_;

	my %parameters;
	open(my $fh, "<$config_file") or die "Could not open $config_file";

	while(my $line = readline($fh))
	{
		chomp $line;
		my ($valid_line) = ($line =~ /^([^#]+)/);
		next if ((not defined $valid_line) or $valid_line eq "");

		my ($key,$value) = ($valid_line =~ /^([^=]+)=(.*)$/);

		die "error: no key in $line" if (not defined $key);
		die "error: no value in $line" if (not defined $value);

		$parameters{$key} = $value;
	}

	close($fh);

	return \%parameters;
}
