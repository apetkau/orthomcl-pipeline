#!/usr/bin/env perl
# setup.pl
# Checks for OrthoMCL dependencies and attempts to write an example configuration file.

use FindBin;
use YAML::Tiny;
use File::Copy;


# dependency modules
use Bio::SeqIO;
use DBD::mysql;
use DBI;
use Getopt::Long;
use Parallel::ForkManager;
use File::Basename;
use Set::Scalar;
use Test::More;
use Text::Table;
use YAML::Tiny;

my $script_dir = $FindBin::Bin;
my $config_dir = "$script_dir/../etc";
my $config_file = "$config_dir/orthomcl-pipeline.conf.default";
my $out_config_file = "$config_dir/orthomcl-pipeline.conf";
my $bin_dir = "$script_dir/../bin";
my $out_bin_file_default = "$bin_dir/orthomcl-pipeline.example";
my $out_bin_file = "$bin_dir/orthomcl-pipeline";

# reading example configuration file
my $yaml = YAML::Tiny->read($config_file);
die "Error: coult not read $config_file" if (not defined $yaml);
my $config = $yaml->[0];

print "Checking for Software dependencies...\n";

my $paths = $config->{'path'};
check_software($paths);

if (-e $out_config_file)
{
	print "Warning: file $out_config_file already exists ... overwrite? (Y/N) ";
	my $choice = <STDIN>;
	chomp $choice;
	if ("yes" eq lc($choic) or "y" eq lc($choice))
	{
		$yaml->write($out_config_file);
		print "Wrote new configuration to $out_config_file\n";
	}
	else
	{
		print "Did not write any new configuration file\n";
	}
}
else
{
	$yaml->write($out_config_file);
	print "Wrote new configuration to $out_config_file\n";
}

if (not -e $out_bin_file)
{
	copy($out_bin_file_default,$out_bin_file) or die "Could not copy ".
		"$out_bin_file_default to $out_bin_file";
	chmod 0766, $out_bin_file;

	print "Wrote executable file to $out_bin_file\n";
	print "Please add directory $bin_dir to PATH\n";
}

# checks software dependencies and fills in paths in YAML data structure
sub check_software
{
	my ($paths) = @_;

	print "\tChecking for OthoMCL ... ";
	my $orthomcl_adjustfasta_path = `which orthomclAdjustFasta`;
	chomp $orthomcl_adjustfasta_path;
	if (not -e $orthomcl_adjustfasta_path)
	{
		die "error: OrthoMCL software could not be found on PATH\n"
	}
	else
	{
		print "OK\n";
	}
	my $orthomcl_path = dirname($orthomcl_adjustfasta_path);
	$paths->{'orthomcl'} = $orthomcl_path;
	
	print "Checking for formatdb ... ";
	my $formatdb_path = `which formatdb`;
	chomp $formatdb_path;
	if (not -e $formatdb_path)
	{
		die "error: formatdb could not be found on PATH\n"
	}
	else
	{
		print "OK\n";
	}
	$paths->{'formatdb'} = $formatdb_path;
	
	print "Checking for blastall ... ";
	my $blastall_path = `which blastall`;
	chomp $blastall_path;
	if (not -e $blastall_path)
	{
		die "error: blastall could not be found on PATH\n"
	}
	else
	{
		print "OK\n";
	}
	$paths->{'blastall'} = $blastall_path;
	
	print "Checking for mcl ... ";
	my $mcl_path = `which mcl`;
	chomp $mcl_path;
	if (not -e $mcl_path)
	{
		die "error: mcl could not be found on PATH\n"
	}
	else
	{
		print "OK\n";
	}
	$paths->{'mcl'} = $mcl_path;
}
