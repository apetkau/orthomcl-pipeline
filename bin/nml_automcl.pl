#!/usr/bin/perl

# Purpose:  Automates running of the orthomcl pipeline.  See http://www.orthomcl.org/cgi-bin/OrthoMclWeb.cgi
# Input: A directory of input fasta files for orthomcl as well as a number of config files.
# Output: Creates a directory with all the orthomcl data sets as well as the groups file.
# Dependencies:  Requires orthomcl, mcl, blast, as well a a cluster environment.
# Authors:  Aaron Petkau <aaron.petkau@phac-aspc.gc.ca>

use strict;
use warnings;

use FindBin;

use YAML::Tiny;
use Schedule::DRMAAc qw( :all );
use Getopt::Long;
use Cwd qw(getcwd abs_path);
use File::Basename qw(basename dirname);
use File::Copy;
use File::Path;
use DBI;
use DBD::mysql;

my $script_dir = $FindBin::Bin;

my $all_fasta_name = 'goodProteins.fasta';
my $blast_result_name = 'blast_results';
my $blast_all_results = "all.fasta";

my $orthoParams; # stores main parameters

sub usage
{
"Usage: ".basename($0)." -i [input dir] -o [output dir] -m [orthmcl config] [Options]
	Options:
	-i|--input-dir: The input directory containing the files to process.
	-o|--output-dir: The output directory for the job.
	-s|--split:  The number of times to split the fasta files for blasting
	-c|--config:  The main config file (optional, overrides default config).
	-m|--orthomcl-config:  The orthomcl config file
	--compliant:  If fasta data is already compliant (headers match, etc).
	--print-config: Prints default config file being used.
	--print-orthomcl-config:  Prints example orthomcl config file.
	-h|--help:  Show help.

	Examples:
	".basename($0)." -i input/ -o output/ -m orthomcl.config
		Runs orthomcl using the input fasta files under input/ and orthomcl.confg as config file.
		Places data in output/.  Gets other parameters (blast, etc) from default config file.

	".basename($0)." -i input/ -o output/ -m orthomcl.config -c automcl.conf
		Runs orthomcl using the given input/output directories.  Overrides parameters (blast, etc)
		from file automcl.conf.

	".basename($0)." --print-config
		Prints default automcl.conf config file (which can then be changed).

	".basename($0)." --print-orthomcl-config
		Prints orthomcl example config file which must be changed to properly run.

	".basename($0)." -i input/ -o output/ -m orthomcl.confg --compliant
		Runs orthmcl with the given input/output/config files.
		Skips the orthomclAdjustFasta stage on input files.\n";
}

sub start_scheduler
{
	my ($drmerr, $drmdiag) = drmaa_init(undef);
	die drmaa_strerror($drmerr),"\n",$drmdiag if ($drmerr);
}

sub stop_scheduler
{
        my ($drmerr,$drmdiag) = drmaa_exit();
        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;
}

sub check_dependencies
{
	my $orthomclbin = $orthoParams->{'path'}->{'orthomcl'};
	my $formatdbbin = $orthoParams->{'path'}->{'formatdb'};
	my $blastallbin = $orthoParams->{'path'}->{'blastall'};
	my $mclbin = $orthoParams->{'path'}->{'mcl'};

	die "Error: orthomcl bin dir not defined" if (not defined $orthomclbin);
	die "Error: orthomcl bin dir \"$orthomclbin\" does not exist" if (not -e $orthomclbin);

	die "Error: orthomclAdjustFasta does not exist in \"$orthomclbin\"" if (not -e "$orthomclbin/orthomclAdjustFasta");

	die "Error: formatdb location not defined" if (not defined $formatdbbin);
	die "Error: formatdb=\"$formatdbbin\" does not exist" if (not -e $formatdbbin);

	die "Error: blastall location not defined" if (not defined $blastallbin);
	die "Error: blastall=\"$blastallbin\" does not exist" if (not -e $blastallbin);

	die "Error: mcl location not defined" if (not defined $mclbin);
	die "Error: mcl=\"$mclbin\" does not exist" if (not -e $mclbin);
}

sub check_database
{
	my ($ortho_config, $log_dir) = @_;

	my $check_database_log = "$log_dir/checkDatabase.log";

	print "\n=Stage: Validate Database=\n";

	die "Undefined orthmcl config file" if (not defined $ortho_config);

	# read orthomcl config file
	my %ortho_params;
	open(my $ortho_h, "<$ortho_config") or die "Could not open orthomcl config file: $ortho_config: $!";
	while(<$ortho_h>)
	{
		my ($valid_line) = ($_ =~ /^([^#]*)/);

		next if (not defined $valid_line or $valid_line eq '');

		my @tokens = split(/=/, $valid_line);
		next if (@tokens <= 1 or (not defined $tokens[0]) or ($tokens[0] eq ''));

		chomp $tokens[0];
		chomp $tokens[1];
		$ortho_params{$tokens[0]} = $tokens[1];
	}
	close($ortho_h);

	my $dbConnect = $ortho_params{'dbConnectString'};
	my $dbLogin = $ortho_params{'dbLogin'};
	my $dbPass = $ortho_params{'dbPassword'};

	die "Error: no dbConnectString in $ortho_config" if (not defined $dbConnect or $dbConnect eq '');
	die "Error: no dbLogin in $ortho_config" if (not defined $dbLogin or $dbLogin eq '');
	die "Error: no dbPassword in $ortho_config" if (not defined $dbPass);

	my $dbh = DBI->connect($dbConnect,$dbLogin,$dbPass, {RaiseError => 1, AutoCommit => 0});
	die "Error connecting to database $dbConnect, user=$dbLogin: ".$DBI::errstr if (not defined $dbh);
	my ($sth,$rv);
	my $database_name;

	eval
	{
		$sth = $dbh->prepare('select database()');
		$rv = $sth->execute;
		die "Could not get database name: ".$dbh->errstr if (not defined $rv);
		my @array = $sth->fetchrow_array;
		$sth->finish;
		die "Error: could not get database name when executing 'select database()'" if (@array <= 0);
		$database_name = $array[0];
		die "Could not get database name when executing 'select database()'" if (not defined $database_name or $database_name eq '');
		die "Attempting to use 'mysql' database in $ortho_config, not gonna touch that" if ($database_name eq 'mysql');

		die "Crazy database name you have there ($database_name), don't like it" if ($database_name !~ /^[0-9,a-z,A-Z\$_\-]+$/);
	};
	if ($@)
	{
		my $error_message = $@;
		$dbh->rollback;
		$dbh->disconnect;
		die "Failed: $error_message";
	}

	eval
	{
		$sth = $dbh->prepare('show tables');
		$rv = $sth->execute;
		$sth->finish;
		die "Error executing \"show tables\" on database $dbConnect: ".$sth->errstr if (not defined $rv);
	};
	if ($@)
	{
		my $err_message = $@;
		$dbh->rollback;
		$dbh->disconnect;
		die "Failed: $err_message";
	}
	
	if ($rv > 0)
	{
		print "Warning: some tables exist already in database $dbConnect, user=$dbLogin, name=$database_name. Do you want to remove (y/n)? ";
		my $response = <>;
		chomp $response;
		if (not ($response eq 'y' or $response eq 'Y' or ($response =~ /^yes$/i)))
		{
			$dbh->rollback;
			$dbh->disconnect;
			die "Tables already exist in database $dbConnect, could not continue.";
		}
		else
		{
			eval
			{	
				print "Executing: 'drop database $database_name'\n";
				$sth = $dbh->prepare("drop database $database_name"); # can't bind database name (causes error)
				$rv = $sth->execute();
				die "Error dropping database: ".$sth->errstr if (not defined $rv);
				
				print "Executing: 'create database $database_name'\n";
				$sth = $dbh->prepare("create database $database_name");
				$rv = $sth->execute();
		
				if (not defined $sth)
				{
					my $errstr = $dbh->errstr;
					die "Error creating database: $errstr: rolling back";
				}
				else
				{
					$dbh->commit;
					print "Successfully removed old database entries\n";
				}
			};
			if ($@)
			{
				my $err_message = $@;
				eval {$dbh->rollback;};
				eval {$dbh->disconnect;};
				die "Failure: $err_message";
			}
		}
	}

	print "\n";

	$dbh->disconnect;
}

sub adjust_fasta
{
	my ($input_dir, $output, $log_dir) = @_;

	my $log = "$log_dir/adjustFasta.log";

	print "\n=Stage: Adjust Fasta=\n";
	my $ortho_adjust_fasta = $orthoParams->{'path'}->{'orthomcl'}.'/orthomclAdjustFasta';

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

	my $ortho_filter_fasta = $orthoParams->{'path'}->{'orthomcl'}.'/orthomclFilterFasta';
	my $min_length = $orthoParams->{'filter'}->{'min_length'};
	my $max_percent_stop = $orthoParams->{'filter'}->{'max_percent_stop'};

	print "\n=Stage: Filter Fasta=\n";

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
	my $input_file = "$input_dir/$all_fasta_name";

	print "\n=Stage: Split Fasta=\n";

	require("$script_dir/lib/split.pl");
	print "splitting $input_file into $split_number pieces\n";
	Split::run($input_file,$split_number,$input_dir,$log);

	print "\n";
}

sub format_database
{
	my ($input_dir, $log_dir) = @_;

	my $log = "$log_dir/formatDatabase.log";
	my $formatdb_log = "$log_dir/formatdb.log";

	my $formatdb = $orthoParams->{'path'}->{'formatdb'};

	print "\n=Stage: Format Database=\n";

	my $database = "$input_dir/$all_fasta_name";

	my $command = "$formatdb -i \"$database\" -p T -l \"$formatdb_log\"";
	print $command;

	system("$command 1>$log 2>&1") == 0 or die "Could not format database";

	print "\n";
}

sub perform_blast
{
	my ($blast_dir, $blast_results_dir, $num_tasks, $blast_log_dir) = @_;

	my $blastbin = $orthoParams->{'path'}->{'blastall'};

	my $command = $blastbin;
	my $task_num = 0;
	my @job_ids;

	print "\n=Stage: Perform Blast=\n";

	# set autoflush
	$| = 1;
	print "performing blasts .";
	start_scheduler();

        my ($drmerr,$jt,$drmdiag,$jobid,$drmps);

	for ($task_num = 1; $task_num < $num_tasks; $task_num++)
	{
		my $blast_params = ['-p', 'blastp', '-i', "$blast_dir/$all_fasta_name.$task_num", '-m', '8',
				    '-d', "$blast_dir/$all_fasta_name", '-o', "$blast_results_dir/$blast_result_name.$task_num"];
		foreach my $key (keys %{$orthoParams->{'blast'}})
		{
			my $value = $orthoParams->{'blast'}->{$key};

			if (defined $value)
			{
				push(@$blast_params, "-$key");
				push(@$blast_params, $value);
			}
		}

        	($drmerr,$jt,$drmdiag) = drmaa_allocate_job_template();
		die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;

		($drmerr,$drmdiag) = drmaa_set_attribute($jt,$DRMAA_REMOTE_COMMAND,$command); #sets the command for the job to be run
		die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;

		($drmerr,$drmdiag) = drmaa_set_attribute($jt,$DRMAA_OUTPUT_PATH,":$blast_log_dir/stdout-$task_num.txt"); #sets the output directory for stdout
	        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;
	
		($drmerr,$drmdiag) = drmaa_set_attribute($jt,$DRMAA_ERROR_PATH,":$blast_log_dir/stderr-$task_num.txt"); #sets the output directory for stdout
	        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;
	
		($drmerr,$drmdiag) = drmaa_set_vector_attribute($jt,$DRMAA_V_ARGV,$blast_params); #sets the list of arguments to be applied to this job
	        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;
	
		($drmerr,$jobid,$drmdiag) = drmaa_run_job($jt); #submits the job to whatever scheduler you're using
	        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;

		($drmerr,$drmdiag) = drmaa_delete_job_template($jt); #clears up the template for this job
        	die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;

		push(@job_ids,$jobid);
	}

	# wait for jobs
	do
	{
		($drmerr, $drmdiag) = drmaa_synchronize(\@job_ids, 10, 0);

		die drmaa_strerror( $drmerr ) . "\n" . $drmdiag
                                if $drmerr and $drmerr != $DRMAA_ERRNO_EXIT_TIMEOUT;

		print ".";
	} while ($drmerr == $DRMAA_ERRNO_EXIT_TIMEOUT);

	print "done\n\n";
	$|=0;

	stop_scheduler();
}

sub load_ortho_schema
{
	my ($ortho_config, $log_dir) = @_;

	print "\n=Stage: Load OrthoMCL Database Schema=\n";

	my $ortho_log = "$log_dir/orthomclSchema.log";
	
	my $orthobin = $orthoParams->{'path'}->{'orthomcl'};
	my $loadbin = "$orthobin/orthomclInstallSchema";

	my $command = "$loadbin \"$ortho_config\" \"$ortho_log\"";

	print "$command\n";
	system("$command 1>$ortho_log 2>&1") == 0 or die "Could not load orthomcl database schema: see $ortho_log";

	print "\n";
}

sub parseblast
{
	my ($blast_results_dir, $blast_load_dir, $ortho_config, $fasta_input, $log_dir) = @_;

	my $parse_blast_log = "$log_dir/parseBlast.log";

	print "\n=Stage: Parse Blast Results=\n";

	my $command = "cat $blast_results_dir/$blast_result_name.* > $blast_load_dir/$blast_all_results";

	# make sure files we merge are all in sync on filesystem
	opendir(my $dh, $blast_results_dir);
	closedir($dh);
	#

	print "$command\n";
	system("$command 2> $parse_blast_log") == 0 or die "Could not concat blast results to $blast_load_dir/$blast_all_results";

	my $orthobin = $orthoParams->{'path'}->{'orthomcl'};
	my $ortho_parser = "$orthobin/orthomclBlastParser";

	$command = "$ortho_parser \"$blast_load_dir/$blast_all_results\" \"$fasta_input\" > \"$blast_load_dir/similarSequences.txt\"";
	print "$command\n";
	system("$command 2>> $parse_blast_log") == 0 or die "Could not run orthomclBlastParser. See $parse_blast_log";

	print "\n";
}

sub ortho_load
{
	my ($ortho_config, $blast_load_dir, $log_dir) = @_;

	my $ortho_log = "$log_dir/orthomclLoadBlast.log";
	my $similar_seqs = "$blast_load_dir/similarSequences.txt";

        my $orthobin = $orthoParams->{'path'}->{'orthomcl'};
        my $loadbin = "$orthobin/orthomclLoadBlast";

	print "\n=Stage: Load Blast Results=\n";

	my $command = "$loadbin \"$ortho_config\" \"$similar_seqs\"";

	print "$command\n";
	system("$command 1>$ortho_log 2>&1") == 0 or die "Could not load $similar_seqs into database. See $ortho_log";

	print "\n";
}

sub ortho_pairs
{
	my ($ortho_config, $log_dir) = @_;

	my $ortho_log = "$log_dir/orthomclPairs.log";

        my $orthobin = $orthoParams->{'path'}->{'orthomcl'};

	my $pairsbin = "$orthobin/orthomclPairs";

	print "\n=Stage: OrthoMCL Pairs=\n";

	my $command = "$pairsbin \"$ortho_config\" \"$ortho_log\" cleanup=yes";

	print "$command\n";
	system($command) == 0 or die "Could not execute $command\n";

	print "\n";
}

sub ortho_dump_pairs
{
	my ($ortho_config, $pairs_dir, $log_dir) = @_;

	my $ortho_log = "$log_dir/orthomclDumpPairs.log";

        my $orthobin = $orthoParams->{'path'}->{'orthomcl'};

	my $pairsbin = "$orthobin/orthomclDumpPairsFiles";

	print "\n=Stage: OrthoMCL Dump Pairs=\n";

	my $cwd = getcwd;
	chdir $pairs_dir or die "Could not change to directory $pairs_dir";

	my $command = "$pairsbin \"$cwd/$ortho_config\"";

	print "$command\n";
	system("$command 1>$ortho_log 2>&1") == 0 or die "Could not execute $command. See $ortho_log\n";

	chdir $cwd;

	print "\n";
}

sub run_mcl
{
	my ($pairs_dir, $log_dir) = @_;

	my $ortho_log = "$log_dir/mcl.log";
	my $mcl_input = "$pairs_dir/mclInput";
	my $mcl_output = "$pairs_dir/mclOutput";

        my $mcl_bin = $orthoParams->{'path'}->{'mcl'};

	print "\n=Stage: Run MCL=\n";

	my $command = "$mcl_bin \"$mcl_input\" --abc -I 1.5 -o \"$mcl_output\"";

	print "$command\n";
	system("$command 1>$ortho_log 2>&1") == 0 or die "Could not execute $command. See $ortho_log\n";

	print "\n";
}

sub mcl_to_groups
{
	my ($pairs_dir, $groups_dir, $log_dir) = @_;

	my $ortho_log = "$log_dir/mclGroups.log";
	my $mcl_output = "$pairs_dir/mclOutput";
	my $groups_file = "$groups_dir/groups.txt";

        my $orthobin = $orthoParams->{'path'}->{'orthomcl'};

	my $groupsbin = "$orthobin/orthomclMclToGroups";

	print "\n=Stage: MCL to Groups=\n";

	my $command = "$groupsbin group_ 1 < \"$mcl_output\" > \"$groups_file\"";

	print "$command\n";
	system("$command 2>$ortho_log") == 0 or die "Could not execute $command. See $ortho_log\n";
	print "Groups File:  $groups_file\n";

	print "\n";
}

sub merge_config_params
{
	my ($default_params, $main_params) = @_;

	return undef if (not defined $default_params and not defined $main_params);
	return $default_params if (not defined $main_params);
	return $main_params if (not defined $default_params);

	return merge_hash_r($default_params, $main_params);
}

sub merge_hash_r
{
	my ($a, $b) = @_;

	my $new_hash = {};
	
	foreach my $key (keys %$a)
	{
		$new_hash->{$key} = $a->{$key};
	}
	
	foreach my $key (keys %$b)
	{
		my $value_b = $b->{$key};
		my $value_a = $new_hash->{$key};

		# if both defined, must merge
		if (defined $value_a and defined $value_b)
		{
			# if the value is another hash, go through another level
			if (defined $value_a and (ref $value_a eq 'HASH'))
			{
				$new_hash->{$key} = merge_hash_r($value_a,$value_b);
			} # else if not another hash, overwrite a with b
			else
			{
				$new_hash->{$key} = $value_b;
			}
		} # if only b defined, copy over to a
		elsif (defined $value_b)
		{
			$new_hash->{$key} = $value_b;
		}
		# else if only a defined, do nothing
	}

	return $new_hash;
}

sub handle_config
{
	my ($default_config, $main_config) = @_;

	my ($default_params,$main_params);
	if (defined $default_config and (-e $default_config))
	{
		my $yaml = YAML::Tiny->read($default_config) or die "Could not read config file ($default_config): ".YAML::Tiny->errstr;
		$default_params = $yaml->[0] or die "Improperly formatted config file $default_config";
	}

	if (defined $main_config and (-e $main_config))
	{
		my $yaml = YAML::Tiny->read($main_config) or die "Could not read config file: ".YAML::Tiny->errstr;
		$main_params = $yaml->[0] or die "Improperly formatted config file $main_config";
	}

	if (not defined $default_params and not defined $main_params)
	{
		die "No parameter file defined\n";
	}
	elsif (not defined $default_params)
	{
		$orthoParams = $main_params;
	}
	elsif (not defined $main_params)
	{
		$orthoParams = $default_params;
	}
	else
	{
		$orthoParams = merge_config_params($default_params, $main_params);
	}
}

##### MAIN #####

my ($input_dir, $output_dir);
my $split_number;
my $orthomcl_config;
my $main_config;
my $compliant;
my $print_config;
my $print_orthomcl_config;
my $help;

my $default_config_path = "$script_dir/etc/automcl.conf";
my $example_ortho_config = "$script_dir/etc/orthomcl.config.example";

if (!GetOptions(
	'i|input-dir=s' => \$input_dir,
	'm|orthomcl-config=s' => \$orthomcl_config,
	'c|config=s' => \$main_config,
	'o|output-dir=s' => \$output_dir,
	's|split=i' => \$split_number,
	'compliant' => \$compliant,
	'print-config' => \$print_config,
	'print-orthomcl-config' => \$print_orthomcl_config,
	'h|help' => \$help))
{
	die "$!".usage;
}

if (defined $help and $help)
{
	print usage;
	exit 0;
}

if (defined $print_config and $print_config)
{
	die "No config file found at $default_config_path" if (not -e $default_config_path);

	open(my $ch, "<$default_config_path") or die "Could not open $default_config_path: $!";
	while(<$ch>)
	{
		print $_;
	}
	close($ch);
	exit 0;
}

if (defined $print_orthomcl_config and $print_orthomcl_config)
{
	die "No config file found at $example_ortho_config" if (not -e $example_ortho_config);

	open(my $ch, "<$example_ortho_config") or die "Could not open $example_ortho_config: $!";
	while(<$ch>)
	{
		print $_;
	}
	close($ch);
	exit 0;
}

print "Starting OrthoMCL pipeline on: ".(localtime)."\n";
my $begin_time = time;

die "Error: no input-dir defined\n".usage if (not defined $input_dir);
die "Error: input-dir not a directory\n".usage if (not -d $input_dir);
die "Error: output-dir not defined\n".usage if (not defined $output_dir);
die "Error: orthomcl-config not defined\n".usage if (not defined $orthomcl_config);
die "Error: orthomcl-config=$orthomcl_config does not exist" if (not -e $orthomcl_config);

if (defined $split_number)
{
	die "Error: split value = $split_number is invalid" if ($split_number !~ /\d+/ or $split_number <= 0);
}

# read config
handle_config($default_config_path, $main_config);
check_dependencies();

if (not defined $split_number)
{
	$split_number = $orthoParams->{'split'};

	if (not defined $split_number or ($split_number !~ /^\d+$/))
	{
		$split_number = 10;
		print STDERR "Warning: split value not defined, defaulting to $split_number\n";
	}
}

if (defined $main_config and not (-e $main_config))
{
	die "Error: config file $main_config does not exist\n".usage;
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

$input_dir = abs_path($input_dir);
$output_dir = abs_path($output_dir);

my $log_dir = "$output_dir/log";
my $blast_log_dir = "$output_dir/log/blast";

my $compliant_dir = "$output_dir/compliant_fasta";
my $blast_dir = "$output_dir/blast_dir";
my $blast_results_dir = "$output_dir/blast_results";
my $blast_load_dir = "$output_dir/blast_load";
my $pairs_dir = "$output_dir/pairs";
my $groups_dir = "$output_dir/groups";

mkdir $log_dir if (not -e $log_dir);
mkdir $blast_log_dir if (not -e $blast_log_dir);
mkdir $compliant_dir if (not -e $compliant_dir);
mkdir $blast_dir if (not -e $blast_dir);
mkdir $blast_results_dir if (not -e $blast_results_dir);
mkdir $blast_load_dir if (not -e $blast_load_dir);
mkdir $pairs_dir if (not -e $pairs_dir);
mkdir $groups_dir if (not -e $groups_dir);

# write out properties used
my $config_out = YAML::Tiny->new;
$config_out->[0] = $orthoParams;
$config_out->write("$log_dir/run.properties");
$config_out = undef;

check_database($orthomcl_config, $log_dir);
load_ortho_schema($orthomcl_config, $log_dir);
if (defined $compliant && $compliant)
{
	rmtree($compliant_dir) or die "Could not delete $compliant_dir: $!";
	system("cp -R \"$input_dir\" \"$compliant_dir\"") == 0 or die "Could not copy $input_dir to $compliant_dir: $!";
}
else
{
	adjust_fasta($input_dir,$compliant_dir, $log_dir);
}
filter_fasta($compliant_dir,$blast_dir, $log_dir);
split_fasta($blast_dir, $split_number, $log_dir);
format_database($blast_dir, $log_dir);
perform_blast($blast_dir, $blast_results_dir, $split_number, $blast_log_dir);
parseblast($blast_results_dir, $blast_load_dir, $orthomcl_config, $compliant_dir, $log_dir);
ortho_load($orthomcl_config, $blast_load_dir, $log_dir);
ortho_pairs($orthomcl_config, $log_dir);
ortho_dump_pairs($orthomcl_config, $pairs_dir, $log_dir);
run_mcl($pairs_dir, $log_dir);
mcl_to_groups($pairs_dir, $groups_dir, $log_dir);

print "Orthomcl Pipeline ended on ".(localtime)."\n";
my $end_time = time;

printf "Took %0.2f minutes to complete\n",(($end_time-$begin_time)/60);
print "Parameters used can be viewed in $orthomcl_config and $log_dir/run.properties\n";
