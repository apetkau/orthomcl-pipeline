#!/usr/bin/env perl

use warnings;
use strict;

use FindBin;

use Test::More;
use Getopt::Long;
use File::Temp qw(tempdir);
use File::Path qw(rmtree);
use File::Copy;

my $script_dir = $FindBin::Bin;

sub usage
{
	return "Usage: $0 -m [orthomcl.config] -s [scheduler]\n".
	       "Options:\n".
	       "\t-m [orthomcl.config]:  A orthomcl config file containing the database login info for testing\n".
	       "\t-s [scheduler]:  The scheduler to use, one of 'fork' or 'sge' (default fork)\n".
	       "\t-t [temp_dir]:  The temporary directory to use, must be accessible by all nodes for sge mode\n";
}

sub compare_groups
{
	my ($file1,$file2) = @_;

	open(my $file1h, "<$file1") or die "Could not open $file1";
	open(my $file2h, "<$file2") or die "Could not open $file2";
	
	my $matched = 1;
	while(my $line1 = readline $file1h)
	{
		my $line2 = readline $file2h;
		chomp ($line1,$line2);

		my @tokens1 = split(/\s+/,$line1);
		my @tokens2 = split(/\s+/,$line2);

		my $group_token1 = shift(@tokens1);
		my $group_token2 = shift(@tokens2);

		my $sorted_line1 = $group_token1.' '.join(' ', sort {$a cmp $b} @tokens1);
		my $sorted_line2 = $group_token2.' '.join(' ', sort {$a cmp $b} @tokens2);
		if ($sorted_line1 ne $sorted_line2)
		{
			print "line1: \"$line1\" not match line2 \"$line2\"";
			$matched=0;
			close($file1h);
			close($file2h);

			return $matched;
		}
	}
	close($file1h);
	close($file2h);

	return $matched;
}

sub setup_parameters
{
	my ($test_dir, $tempdir, $ortho_param) = @_;

	print "README:\n";
	open(my $th, "$test_dir/README");
	while(<$th>){print $_;}
	close($th);
	
	# write out orthomcl config file used for test (including database login info)
	my $test_ortho_config = "$tempdir/orthomcl.config";
	copy("$test_dir/etc/orthomcl.config", $test_ortho_config) or die "Could not copy $test_dir/etc/orthomcl.config: $!";
	open (my $test_ortho_config_h, ">>$test_ortho_config");
	print $test_ortho_config_h 'dbVendor='.$ortho_param->{'dbVendor'};
	print $test_ortho_config_h 'dbConnectString='.$ortho_param->{'dbConnectString'};
	print $test_ortho_config_h 'dbLogin='.$ortho_param->{'dbLogin'};
	print $test_ortho_config_h 'dbPassword='.$ortho_param->{'dbPassword'};
	close($test_ortho_config_h);

	return $test_ortho_config;
}

my $ortho_conf;
my $scheduler;
my $temp_root;
my %ortho_param;
if (!GetOptions(
	'm|orthomcl-config=s' => \$ortho_conf,
	's|scheduler=s' => \$scheduler,
	't|temp=s' => \$temp_root
	))
{
	die "$!\n".usage;
}

if (not defined $ortho_conf)
{
	die "Error: need to pass ortho conf file containing database info\n".usage;
}
elsif (not -e $ortho_conf)
{
	die "Error: ortho_conf=$ortho_conf does not exist";
}
else
{
	open(my $f, "<$ortho_conf") or die "Could not open $ortho_conf";
	
	while(<$f>)
	{
		my ($valid_line) = ($_ =~ /^([^#]+)/);

		if (defined $valid_line and $valid_line ne '')
		{
			my @tokens = split(/=/,$valid_line);

			$ortho_param{$tokens[0]} = $tokens[1];
		}
	}
	close($f);

	die "Error: no dbVendor defined" if (not defined $ortho_param{'dbVendor'});
	die "Error: no dbConnectString defined" if (not defined $ortho_param{'dbConnectString'});
	die "Error: no dbLogin defined" if (not defined $ortho_param{'dbLogin'});
	die "Error: no dbPassword defined" if (not defined $ortho_param{'dbPassword'});
}

if (not defined $scheduler)
{
    $scheduler = 'fork';
}
elsif ($scheduler ne 'fork' and $scheduler ne 'sge')
{
	die "Error: invalid scheduler=$scheduler\n".usage;
}

if (not defined $temp_root)
{
	if (defined $ENV{'HOME'})
	{
		$temp_root = $ENV{'HOME'};
	}
	else
	{
		$temp_root = "/tmp";
	}
}
elsif (not -d $temp_root)
{
	die "Error: temp=$temp_root not a directory";
}

if (not -w $temp_root)
{
	die "Error: temp=$temp_root is not writeable by current user";
}

print "Test using scheduler $scheduler\n\n";

my $data_dir;

# CASE
$data_dir = "$script_dir/data/basic";

print "TESTING NON-COMPLIANT INPUT\n";
opendir(my $data_dirh, $data_dir) or die "Could not open $data_dir";
my @dirs = grep {/^[^\.]/} readdir($data_dirh);
closedir($data_dirh);

for my $test_num (@dirs)
{
	print "TESTING FULL PIPELINE RUN $test_num\n";

	my $tempdir = tempdir('automcl.XXXXXX', DIR=> $temp_root);
	my $out_dir = "$tempdir/output";
	my $test_dir = "$data_dir/$test_num";

	my ($test_ortho_config) = setup_parameters($test_dir, $tempdir, \%ortho_param);
	
	my $test_command1 = "$script_dir/../bin/nml_automcl --scheduler $scheduler --yes -c $test_dir/etc/automcl.conf -i $test_dir/input -o $out_dir -m $test_ortho_config 2>$tempdir/nml_automcl.err.log 1>$tempdir/nml_automcl.out.log";
	
	#print $test_command1,"\n";
	system($test_command1) == 0 or die "Could not execute command $test_command1\n";
	
	my $matched = compare_groups("$test_dir/groups/groups.txt", "$out_dir/groups/groups.txt");
	ok ($matched, "Expected matched returned groups file");

	print "\n";
	
	rmtree($tempdir);
}

# CASE
$data_dir = "$script_dir/data/compliant";

print "TESTING COMPLIANT INPUT\n";
opendir($data_dirh, $data_dir) or die "Could not open $data_dir";
@dirs = grep {/^[^\.]/} readdir($data_dirh);
closedir($data_dirh);

for my $test_num (@dirs)
{
	print "TESTING FULL PIPELINE RUN $test_num\n";

	my $tempdir = tempdir('automcl.XXXXXX', DIR=> "$temp_root");
	my $out_dir = "$tempdir/output";
	my $test_dir = "$data_dir/$test_num";

	my ($test_ortho_config) = setup_parameters($test_dir, $tempdir, \%ortho_param);
	
	my $test_command1_non_comp = "$script_dir/../bin/nml_automcl --scheduler $scheduler --yes -c $test_dir/etc/automcl.conf -i $test_dir/input -o $out_dir -m $test_ortho_config 2>$tempdir/nml_automcl_noncompliant.err.log 1>$tempdir/nml_automcl_noncompliant.out.log";
	my $ret_value = system($test_command1_non_comp);
	ok($ret_value ne 0, "No compliant parameter successfully caught");

	my $test_command1 = "$script_dir/../bin/nml_automcl --compliant --scheduler $scheduler --yes -c $test_dir/etc/automcl.conf -i $test_dir/input -o $out_dir -m $test_ortho_config 2>$tempdir/nml_automcl_compliant.err.log 1>$tempdir/nml_automcl_compliant.out.log";
	
	#print $test_command1,"\n";
	system($test_command1) == 0 or die "Could not execute command $test_command1\n";
	
	my $matched = compare_groups("$test_dir/groups/groups.txt", "$out_dir/groups/groups.txt");
	ok ($matched, "Pipeline succeeded with compliant parameter. Expected matched returned groups file");

	print "\n";
	
	rmtree($tempdir);
}

done_testing();

