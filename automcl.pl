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
	-o|--output-dir: The output directory for the job.\n";
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
	my ($input_dir, $output) = @_;

	my $ortho_adjust_fasta = $AutoConfig::params{'orthomcl'}{'bin'}.'/orthomclAdjustFasta';

	opendir(my $dh, $input_dir) or die "Could not open directory $input_dir";

	my $cwd = getcwd;
	chdir $output or die "Could not change to directory $output";

	my $file = readdir($dh);
	while (defined $file)
	{
		my $base = basename($file, ('.faa','.fasta'));

		system("$ortho_adjust_fasta $base \"$input_dir/$file\" 1") == 0 or die "Error running orthomclAdjustFasta for file $file";

		$file = readdir($dh);
	}
	closedir($dh);

	chdir $cwd;
}

my ($input_dir, $output_dir);

if (!GetOptions(
	'i|input-dir=s' => \$input_dir,
	'o|output-dir=s' => \$output_dir))
{
	die "$!".usage;
}

check_dependencies();

die "Error: no input-dir defined\n".usage if (not defined $input_dir);
die "Error: input-dir not a directory\n".usage if (not -d $input_dir);
die "Error: output-dir not defined\n".usage if (not defined $output_dir);

$input_dir = abs_path($input_dir);
$output_dir = abs_path($output_dir);

if (-e $output_dir)
{
    print "Warning: directory \"$output_dir\" already exists, are you sure you want to store data here [Y]? ";
    my $response = <>;
    chomp $response;
    if (not ($response eq 'y' or $response eq 'Y' or $response eq ''))
    {
        die "Directory \"$output_dir\" already exists, could not continue.";
    }
}
else
{
	mkdir $output_dir;
}

my $compliant_dir = "$output_dir/compliant_fasta";
mkdir $compliant_dir if (not -e $compliant_dir);

adjust_fasta($input_dir,$compliant_dir);
