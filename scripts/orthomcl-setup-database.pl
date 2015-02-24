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

my $usage = "Usage: ".basename($0)."\n --user [user] --password [password] --host [host] --database [database] --outfile [outfile]\n".
"\nChecks for a database connection, creates a database and generates an orthomcl config file with the given parameters.\n".
"Note this script requires a MySQL database.\n".
"The database name provided does not need to exist and will be created.\n".
"Ensure the user has permissions to create, modify and delete databases.\n\n";

my ($user,$password,$host, $database, $outfile);
if (not GetOptions(
	'user=s' => \$user,
	'password=s' => \$password,
	'host=s' => \$host,
	'database=s' => \$database,
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

print STDERR "Connecting to mysql and creating database $database on host $host with user $user ...";
my $db_connect = "dbi:mysql:mysql:$host:mysql_local_infile=1";
my $dbh = DBI->connect($db_connect,$user,$password, {RaiseError => 1, AutoCommit => 0});
if (not defined $dbh)
{
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
    # Database doesn't already exists. Check if config file already exists.
    if (-e $outfile)
    {
        print STDERR "Warning: file $outfile already exists ... overwrite? (Y/N) ";
        my $choice = <STDIN>;
        chomp $choice;
        if ("yes" eq lc($choice) or "y" eq lc($choice))
        {
           print STDERR "\n$outfile will be overwritten\n";
        }
        else
        {
        	close_db();
            die "\nConfig file will not be overwritten, please choose a new name and try again!"; 
        }
    }     
   
    $dbh->do("CREATE DATABASE $database")
    or die "\nCouldn't create database $database";
    print STDERR "database $database created ...OK\n";
    close_db();
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