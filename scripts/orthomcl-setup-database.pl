#!/usr/bin/env perl
# setup_database.pl
# Purpose: used to create and setup a configuration file for
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

my $usage = "Usage: ".basename($0)."\n --user [user] --password [password] --host [host] --database [database] --outfile [outfile] --no-create-database\n".
"\nChecks for a database connection, creates a database (when not suppressed) and generates an orthomcl config file with the given parameters.\n".
"Note this script requires a MySQL database.\n".
"The database name provided does not need to exist and will be created unless option --no-create-database is used.\n".
"Ensure the user has permissions to create, modify and delete databases.\n\n";

my ($user,$password,$host, $database, $outfile, $no_create_db );
if (not GetOptions(
	'user=s' => \$user,
	'password=s' => \$password,
	'host=s' => \$host,
	'database=s' => \$database,
	'no-create-database' => \$no_create_db,
	'outfile=s' => \$outfile))
{
	die "$!\n".$usage;
}

if (not (defined $user and
	 defined $password and
	 defined $host and
	 defined $database and
	 defined $outfile))
{
	die "missing database information\n".$usage;
}

my $parameters = parse_config($default_config);
my $dbh;

# Check if config file already exists.
if (-e $outfile)
{
    print STDERR "Warning: file $outfile already exists ... overwrite? (Y/N) ";
    my $choice = <STDIN>;
    chomp $choice;
    if ("yes" eq lc($choice) or "y" eq lc($choice))
    {
       print STDERR "\nConfig file, $outfile will be overwritten\n";
    }
    else
    {
        die "\nConfig file will not be overwritten, please choose a new name and try again!"; 
    }
} 

if(defined $no_create_db)
{
	# User already has a database to use
	# Check that can connect to database
	print STDERR "Connecting to database $database on host $host with user $user ...\n";
	my $db_connect = "dbi:mysql:$database:$host:mysql_local_infile=1";
	$dbh = DBI->connect($db_connect,$user,$password, {RaiseError => 0, AutoCommit => 0});
	if (not defined $dbh)
	{
		# Not able to connect to previously created database
		die "error connecting to database (please ensure database exists and try again)";
	}
	else
	{
		print STDERR "OK\n";
		close_db();
	}
} 
else
{
	# User wants to create a new database
	# Connect to server and create new database
	print STDERR "Connecting to mysql and creating database $database on host $host with user $user ...\n";
	my $db_connect_create = "dbi:mysql:mysql:$host:mysql_local_infile=1";
	$dbh = DBI->connect($db_connect_create,$user,$password, {RaiseError => 0, AutoCommit => 0});
	if (not defined $dbh)
	{
		# not able to connect to my sql database
		die "error connecting to database";
	}
	else
	{
		print STDERR "OK\n";
	}

	my $rc = $dbh->do("SHOW DATABASES LIKE '$database'");
	if ($rc == 1)
	{
		close_db();
	    die "Database $database already exists, please choose a new database name";
	}
	else
	{
	    $dbh->do("CREATE DATABASE $database")
	    or die "\nCouldn't create database $database";
	    print STDERR "database $database created ...OK\n";
	    close_db();
	}
}
# once database is created, create the db_connect_string to use in config file
my $db_connect_string = "dbi:mysql:$database:$host:mysql_local_infile=1";

$parameters->{'dbConnectString'} = $db_connect_string;
$parameters->{'dbLogin'} = $user;
$parameters->{'dbPassword'} = $password;

write_config($parameters);

sub write_config
{
	my ($parameters) = @_;

	unless(open FILE,'>',$outfile){
		die "Unable to create $outfile\n"
	}
	foreach my $key (sort {$a cmp $b} keys %$parameters)
	{
		my $value = $parameters->{$key};
		print FILE "$key=$value\n";
	}
    print STDERR "Config file $outfile created.\n";
	close FILE;
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

sub close_db
{
    $dbh->disconnect();
}