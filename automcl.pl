#!/usr/bin/perl

use strict;
use warnings;

use FindBin;

use lib $FindBin::Bin;
use AutoConfig;

use Getopt::Long;
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



