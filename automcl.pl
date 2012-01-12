#!/usr/bin/perl

use strict;
use warnings;

use FindBin;

use lib $FindBin::Bin;
use AutoConfig;

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

sub usage
{
"Usage: ".basename($0)." -i [input dir] -o [output dir] -m [orthmcl config] [Options]
	Options:
	-i|--input-dir: The input directory containing the files to process.
	-o|--output-dir: The output directory for the job.
	-s|--split:  The number of times to split the fasta files for blasting
	-m|--orthomcl-config:  The orthomcl config file
	--compliant:  If fasta data is already compliant (headers match, etc).
	-h|--help:  Show help.\n";
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
	my $orthomclbin = $AutoConfig::params{'orthomcl'}{'bin'};
	my $formatdbbin = $AutoConfig::params{'bin'}{'formatdb'};
	my $blastallbin = $AutoConfig::params{'bin'}{'blastall'};

	die "Error: orthomcl bin dir not defined" if (not defined $orthomclbin);
	die "Error: orthomcl bin dir \"$orthomclbin\" does not exist" if (not -e $orthomclbin);

	die "Error: orthomclAdjustFasta does not exist in \"$orthomclbin\"" if (not -e "$orthomclbin/orthomclAdjustFasta");

	die "Error: formatdb location not defined" if (not defined $formatdbbin);
	die "Error: formatdb=\"$formatdbbin\" does not exist" if (not -e $formatdbbin);

	die "Error: blastall location not defined" if (not defined $blastallbin);
	die "Error: blastall=\"$blastallbin\" does not exist" if (not -e $blastallbin);
}

sub check_database
{
	my ($ortho_config, $log_dir) = @_;

	my $check_database_log = "$log_dir/checkDatabase.log";

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
	my $input_file = "$input_dir/$all_fasta_name";

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

	my $formatdb = $AutoConfig::params{'bin'}{'formatdb'};

	my $database = "$input_dir/$all_fasta_name";

	my $command = "$formatdb -i \"$database\" -p T -l \"$formatdb_log\"";
	print $command;

	system("$command 1>$log 2>&1") == 0 or die "Could not format database";

	print "\n";
}

sub perform_blast
{
	my ($blast_dir, $blast_results_dir, $num_tasks, $blast_log_dir) = @_;

	my $blastbin = $AutoConfig::params{'bin'}{'blastall'};

	my $command = $blastbin;
	my $task_num = 0;
	my @job_ids;

	# set autoflush
	$| = 1;
	print "performing blasts ";
	start_scheduler();

        my ($drmerr,$jt,$drmdiag,$jobid,$drmps);

	for ($task_num = 1; $task_num < $num_tasks; $task_num++)
	{
		my $blast_params = ['-p', 'blastp', '-i', "$blast_dir/$all_fasta_name.$task_num",
				    '-d', "$blast_dir/$all_fasta_name", '-o', "$blast_results_dir/$blast_result_name.$task_num"];
		foreach my $key (keys %{$AutoConfig::params{'blast'}})
		{
			my $value = $AutoConfig::params{'blast'}{$key};

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

	my $ortho_log = "$log_dir/orthomclSchema.log";
	
	my $orthobin = $AutoConfig::params{'orthomcl'}{'bin'};
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

	my $command = "cat $blast_results_dir/$blast_result_name.* > $blast_load_dir/$blast_all_results";

	print "$command\n";
	system("$command 2> $parse_blast_log") == 0 or die "Could not concat blast results to $blast_load_dir/$blast_all_results";

	my $orthobin = $AutoConfig::params{'orthomcl'}{'bin'};
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

        my $orthobin = $AutoConfig::params{'orthomcl'}{'bin'};
        my $loadbin = "$orthobin/orthomclLoadBlast";

	my $command = "$loadbin \"$ortho_config\" \"$similar_seqs\"";

	print "$command\n";
	system("$command 1>$ortho_log 2>&1") == 0 or die "Could not load $similar_seqs into database. See $ortho_log";

	print "\n";
}

sub ortho_pairs
{
	my ($ortho_config, $log_dir) = @_;

	my $ortho_log = "$log_dir/orthomclPairs.log";

        my $orthobin = $AutoConfig::params{'orthomcl'}{'bin'};

	my $pairsbin = "$orthobin/orthomclPairs";

	my $command = "$pairsbin \"$ortho_config\" \"$ortho_log\" cleanup=yes";

	print "$command\n";
	system($command) == 0 or die "Could not execute $command\n";

	print "\n";
}

sub ortho_dump_pairs
{
	my ($ortho_config, $pairs_dir, $log_dir) = @_;

	my $ortho_log = "$log_dir/orthomclDumpPairs.log";

        my $orthobin = $AutoConfig::params{'orthomcl'}{'bin'};

	my $pairsbin = "$orthobin/orthomclDumpPairsFiles";

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

        my $mcl_bin = $AutoConfig::params{'bin'}{'mcl'};

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

        my $orthobin = $AutoConfig::params{'orthomcl'}{'bin'};

	my $groupsbin = "$orthobin/orthomclMclToGroups";

	my $command = "$groupsbin group_ 1 < \"$mcl_output\" > \"$groups_file\"";

	print "$command\n";
	system("$command 2>$ortho_log") == 0 or die "Could not execute $command. See $ortho_log\n";
	print "Groups File:  $groups_file\n";

	print "\n";
}

##### MAIN #####

my ($input_dir, $output_dir);
my $split_number;
my $orthomcl_config;
my $help;
my $compliant;

if (!GetOptions(
	'i|input-dir=s' => \$input_dir,
	'm|orthomcl-config=s' => \$orthomcl_config,
	'o|output-dir=s' => \$output_dir,
	's|split=i' => \$split_number,
	'compliant' => \$compliant,
	'h|help' => \$help))
{
	die "$!".usage;
}

if (defined $help and $help)
{
	print usage;
	exit 0;
}

check_dependencies();

die "Error: no input-dir defined\n".usage if (not defined $input_dir);
die "Error: input-dir not a directory\n".usage if (not -d $input_dir);
die "Error: output-dir not defined\n".usage if (not defined $output_dir);
die "Error: orthomcl-config not defined\n".usage if (not defined $orthomcl_config);
die "Error: orthomcl-config=$orthomcl_config does not exist" if (not -e $orthomcl_config);

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
