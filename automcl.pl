#!/usr/bin/perl

use strict;
use warnings;

use FindBin;

use lib $FindBin::Bin;
use AutoConfig;

use Getopt::Long;
use Cwd qw(getcwd abs_path);
use File::Basename qw(basename dirname);

my $script_dir = $FindBin::Bin;

sub usage
{
"Usage: ".basename($0)." -i [input dir] -o [output dir] [Options]
	Options:
	-i|--input-dir: The input directory containing the files to process.
	-o|--output-dir: The output directory for the job.
	-s|--split:  The number of times to split the fasta files for blasting\n";
}

sub check_dependencies
{
	my $orthomclbin = $AutoConfig::params{'orthomcl'}{'bin'};
	die "Error: orthomcl bin dir not defined" if (not defined $orthomclbin);
	die "Error: orthomcl bin dir \"$orthomclbin\" does not exist" if (not -e $orthomclbin);

	die "Error: orthomclAdjustFasta does not exist in \"$orthomclbin\"" if (not -e "$orthomclbin/orthomclAdjustFasta");
}

sub adjust_fasta
{
	my ($input_dir, $output, $log_dir) = @_;

	my $log = "$log_dir/adjustFasta.log";

	my $ortho_adjust_fasta = $AutoConfig::params{'orthomcl'}{'bin'}.'/orthomclAdjustFasta';

	opendir(my $dh, $input_dir) or die "Could not open directory $input_dir";

	my $cwd = getcwd;
	chdir $output or die "Could not change to directory $output";

	my $file = readdir($dh);
	while (defined $file)
	{
		my $base = basename($file, ('.faa','.fasta'));

		if ($base ne $file) # if file had correct extension
		{
			my $command = "$ortho_adjust_fasta $base \"$input_dir/$file\" 1";

			print "$command\n";
			system("$command > $log 2>&1") == 0 or die "Error running orthomclAdjustFasta for file $file. Check log $log";
		}

		$file = readdir($dh);
	}
	closedir($dh);

	print "\n";

	chdir $cwd;
}

sub filter_fasta
{
	my ($input_dir, $output_dir, $log_dir) = @_;

	my $log = "$log_dir/filterFasta.log";

	my $ortho_filter_fasta = $AutoConfig::params{'orthomcl'}{'bin'}.'/orthomclFilterFasta';
	my $min_length = $AutoConfig::params{'filter'}{'min_length'};
	my $max_percent_stop = $AutoConfig::params{'filter'}{'max_percent_stop'};

	my $cwd = getcwd;
	chdir $output_dir or die "Could not change to directory $output_dir";
	my $command = "$ortho_filter_fasta \"$input_dir\" $min_length $max_percent_stop";
	print "$command\n";

	system("$command 1> $log 2>&1") == 0 or die "Failed for command $command. Check log $log";

	print "\n";
 
	chdir $cwd;
}

sub split_fasta
{
	my ($input_dir, $split_number, $log_dir) = @_;

	my $log = "$log_dir/split.log";
	my $input_file = "$input_dir/goodProteins.fasta";

	require("$script_dir/lib/split.pl");
	print "splittting $input_file into $split_number pieces\n";
	Split::run($input_file,$split_number,$input_dir,$log);

	print "\n";
}

my ($input_dir, $output_dir);
my $split_number;

if (!GetOptions(
	'i|input-dir=s' => \$input_dir,
	'o|output-dir=s' => \$output_dir,
	's|split=i' => \$split_number))
{
	die "$!".usage;
}

check_dependencies();

die "Error: no input-dir defined\n".usage if (not defined $input_dir);
die "Error: input-dir not a directory\n".usage if (not -d $input_dir);
die "Error: output-dir not defined\n".usage if (not defined $output_dir);

if (defined $split_number)
{
	die "Error: split value = $split_number is invalid" if ($split_number !~ /\d+/ or $split_number <= 0);
}

$input_dir = abs_path($input_dir);
$output_dir = abs_path($output_dir);

if (not defined $split_number)
{
	$split_number = 10;
	print STDERR "Warning: split value not defined, defaulting to $split_number\n";
}

if (-e $output_dir)
{
    print "Warning: directory \"$output_dir\" already exists, are you sure you want to store data here [Y]? ";
    my $response = <>;
    chomp $response;
    if (not ($response eq 'y' or $response eq 'Y'))
    {
        die "Directory \"$output_dir\" already exists, could not continue.";
    }
}
else
{
	mkdir $output_dir;
}

my $log_dir = "$output_dir/log";

my $compliant_dir = "$output_dir/compliant_fasta";
my $blast_dir = "$output_dir/blast_dir";

mkdir $log_dir if (not -e $log_dir);
mkdir $compliant_dir if (not -e $compliant_dir);
mkdir $blast_dir if (not -e $blast_dir);

adjust_fasta($input_dir,$compliant_dir, $log_dir);
filter_fasta($compliant_dir,$blast_dir, $log_dir);
split_fasta($blast_dir, $split_number, $log_dir);
