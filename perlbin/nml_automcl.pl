#!/usr/bin/perl

# Purpose:  Automates running of the orthomcl pipeline.  See http://www.orthomcl.org/cgi-bin/OrthoMclWeb.cgi
# Input: A directory of input fasta files for orthomcl as well as a number of config files.
# Output: Creates a directory with all the orthomcl data sets as well as the groups file.
# Dependencies:  Requires orthomcl, mcl, blast, as well a a cluster environment.
# Authors:  Aaron Petkau <aaron.petkau@phac-aspc.gc.ca>

use strict;
use warnings;

use FindBin;

use lib $FindBin::Bin.'/../lib';

use File::Spec;
use YAML::Tiny;
use Getopt::Long;
use Cwd qw(getcwd abs_path);
use File::Basename qw(basename dirname);
use File::Copy;
use File::Path;
use DBI;
use DBD::mysql;
use Bio::SeqIO;

my $job_runner = undef;

my @valid_fasta_extensions = ('.faa','.fasta');

my $script_dir = $FindBin::Bin;

my $default_config_path = "$script_dir/../etc/automcl.conf";
my $example_ortho_config = "$script_dir/../etc/orthomcl.config.example";

my $all_fasta_name = 'goodProteins.fasta';
my $blast_result_name = 'blast_results';
my $blast_all_results = "all.fasta";

my $orthoParams; # stores main parameters

my $yes = undef;

sub usage
{
"Usage: nml_automcl -i [input dir] -o [output dir] -m [orthmcl config] [Options]
	Options:
	-i|--input-dir: The input directory containing the files to process.
	-o|--output-dir: The output directory for the job.
	-s|--split:  The number of times to split the fasta files for blasting
	-c|--config:  The main config file (optional, overrides default config).
	-m|--orthomcl-config:  The orthomcl config file
	--compliant:  If fasta data is already compliant (headers match, etc).
	--print-config: Prints default config file being used.
	--print-orthomcl-config:  Prints example orthomcl config file.
	--yes: Automatically answers yes to every question (could overwrite/delete old data).
	--scheduler: Defined scheduler (sge or fork).
	-h|--help:  Show help.

	Examples:
	nml_automcl -i input/ -o output/ -m orthomcl.config
		Runs orthomcl using the input fasta files under input/ and orthomcl.confg as config file.
		Places data in output/.  Gets other parameters (blast, etc) from default config file.

	nml_automcl -i input/ -o output/ -m orthomcl.config -c automcl.conf
		Runs orthomcl using the given input/output directories.  Overrides parameters (blast, etc)
		from file automcl.conf.

	nml_automcl --print-config
		Prints default automcl.conf config file (which can then be changed).

	nml_automcl --print-orthomcl-config
		Prints orthomcl example config file which must be changed to properly run.

	nml_automcl -i input/ -o output/ -m orthomcl.confg --compliant
		Runs orthmcl with the given input/output/config files.
		Skips the orthomclAdjustFasta stage on input files.\n";
}

sub set_scheduler
{
	my ($scheduler) = @_;

	if (not defined $scheduler)
	{
		warn "scheduler not set. defaulting to using 'fork'";
		require("$script_dir/../lib/AutoMCL/JobManager/Fork.pm");
		$job_runner = new AutoMCL::JobManager::Fork;
	}
	elsif ($scheduler eq 'sge')
	{
 		require("$script_dir/../lib/AutoMCL/JobManager/SGE.pm");
		$job_runner = new AutoMCL::JobManager::SGE;
	}
	elsif ($scheduler eq 'fork')
	{
		require("$script_dir/../lib/AutoMCL/JobManager/Fork.pm");
		$job_runner = new AutoMCL::JobManager::Fork;
	}
	else
	{
		die "Error: scheduler set to invalid parameter \"$scheduler\". Must be either 'sge' or 'fork'.  Check file $default_config_path or the passed config file.";
	}
}

sub check_dependencies
{
	my $orthomclbin = $orthoParams->{'path'}->{'orthomcl'};
	my $formatdbbin = $orthoParams->{'path'}->{'formatdb'};
	my $blastallbin = $orthoParams->{'path'}->{'blastall'};
	my $mclbin = $orthoParams->{'path'}->{'mcl'};
	my $scheduler = $orthoParams->{'scheduler'};

	die "Error: orthomcl bin dir not defined" if (not defined $orthomclbin);
	die "Error: orthomcl bin dir \"$orthomclbin\" does not exist" if (not -e $orthomclbin);

	die "Error: orthomclAdjustFasta does not exist in \"$orthomclbin\"" if (not -e "$orthomclbin/orthomclAdjustFasta");

	die "Error: formatdb location not defined" if (not defined $formatdbbin);
	die "Error: formatdb=\"$formatdbbin\" does not exist" if (not -e $formatdbbin);

	die "Error: blastall location not defined" if (not defined $blastallbin);
	die "Error: blastall=\"$blastallbin\" does not exist" if (not -e $blastallbin);

	die "Error: mcl location not defined" if (not defined $mclbin);
	die "Error: mcl=\"$mclbin\" does not exist" if (not -e $mclbin);

	set_scheduler($scheduler);
}

sub check_database
{
	my ($stage_num, $ortho_config, $log_dir) = @_;

	my $check_database_log = "$log_dir/checkDatabase.log";

	print "\n=Stage $stage_num: Validate Database=\n";
	my $begin_time = time;

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
		print "Warning: some tables exist already in database $dbConnect, user=$dbLogin, database_name=$database_name. Do you want to remove (y/n)? ";
		my $response = $yes || <>;
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

	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;
	print "\n";

	$dbh->disconnect;
}

sub validate_files
{
	my ($stage_num, $input_dir, $compliant, $log_dir) = @_;

	print "\n=Stage $stage_num: Validate Files =\n";
	my $begin_time = time;

	opendir(my $dh, $input_dir) or die "Could not open directory $input_dir: $!";
	my $file = readdir($dh);
	my $file_count;
	my %seq_names; # checking uniqueness of seq names
	while (defined $file)
	{
		my $base = basename($file, @valid_fasta_extensions);
		if ($base ne $file)
		{
			print "Validating $file ... ";
			my $file_path = "$input_dir/$file";
			my $file_io = Bio::SeqIO->new(-file => $file_path, 'Fasta') or die "Could not open up file $file_path: $!";
			my $seq_count = 0;
			my %gene_names; # checking uniqueness of gene
			my $current_seq_name = $base;

			if (not exists $seq_names{$current_seq_name})
			{
				$seq_names{$current_seq_name} = 1;
			}
			else
			{
				die "Error: file $input_dir/$file uses already existant sequence name $current_seq_name";
			}

			while (my $seq = $file_io->next_seq)
			{
				my $seq_id = $seq->display_id;
				my $error_message = "Error: file $input_dir/$file contains invalid header for \"$seq_id\"";

				# check headers
				if ($compliant)
				{
					my ($name, $gene) = ($seq_id =~ /^([^\|]+)\|(\S+)/);
					my $remove_message = "Perhaps try removing --compliant to format files.";

					die $error_message.": missing sequence name.\n$remove_message" if (not defined $name);
					die $error_message.": sequence name not equal to $current_seq_name.\n$remove_message" if ($name ne $current_seq_name);
					die $error_message.": missing gene name.\n$remove_message" if ((not defined $gene) or $gene eq '');

					if (not exists $gene_names{$gene})
					{
						$gene_names{$gene} = 1;
					}
					else
					{
						die $error_message.": gene \"$gene\" not unique across file";
					}
				}
				else
				{
					die $error_message.": files not marked as compliant but found compliant header.\n"
							  ."Perhaps try adding --compliant, or checking files." if ($seq_id =~ /^[^\|]+\|\S+/);
					my ($gene) = ($seq_id =~ /^(\S+)/);

					if ((not defined $gene) or $gene eq '')
					{
						die $error_message.": missing gene name";
					}
					else
					{
						if (not exists $gene_names{$gene})
						{
							$gene_names{$gene} = 1;
						}
						else
						{
							die $error_message.": gene \"$gene\" not unique across file";
						}
					}
				}

				# check sequence
				die "Error: file $file_path contains a sequence (".$seq->display_id.") with an undefined alphabet" if (not defined $seq->alphabet);
				die "Error: file $file_path contains a sequence (".$seq->display_id.") containing non-protein alphabet (".$seq->alphabet.")" if ($seq->alphabet ne 'protein');

				$seq_count++;
			}

			print "$seq_count sequences\n";

			$file_count++;
		}

		$file = readdir($dh);
	}
	closedir($dh);

	print "Validated $file_count files\n";
	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;
}

sub adjust_fasta
{
	my ($stage_num, $input_dir, $output, $log_dir) = @_;

	my $log = "$log_dir/adjustFasta.log";

	print "\n=Stage $stage_num: Adjust Fasta=\n";
	my $begin_time = time;
	my $ortho_adjust_fasta = $orthoParams->{'path'}->{'orthomcl'}.'/orthomclAdjustFasta';

	opendir(my $dh, $input_dir) or die "Could not open directory $input_dir";

	my $cwd = getcwd;
	chdir $output or die "Could not change to directory $output";

	my $file = readdir($dh);
	while (defined $file)
	{
		my $base = basename($file, @valid_fasta_extensions);

		if ($base ne $file) # if file had correct extension
		{
			my $command = "$ortho_adjust_fasta $base \"$input_dir/$file\" 1";

			print "$command\n";
			system("$command > $log 2>&1") == 0 or die "Error running orthomclAdjustFasta for file $file. Check log $log";
		}

		$file = readdir($dh);
	}
	closedir($dh);

	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;
	print "\n";

	chdir $cwd;
}

sub filter_fasta
{
	my ($stage_num, $input_dir, $output_dir, $log_dir) = @_;

	my $log = "$log_dir/filterFasta.log";

	my $ortho_filter_fasta = $orthoParams->{'path'}->{'orthomcl'}.'/orthomclFilterFasta';
	my $min_length = $orthoParams->{'filter'}->{'min_length'};
	my $max_percent_stop = $orthoParams->{'filter'}->{'max_percent_stop'};

	print "\n=Stage $stage_num: Filter Fasta=\n";
	my $begin_time = time;

	my $cwd = getcwd;
	chdir $output_dir or die "Could not change to directory $output_dir";
	my $command = "$ortho_filter_fasta \"$input_dir\" $min_length $max_percent_stop";
	print "$command\n";

	system("$command 1> $log 2>&1") == 0 or die "Failed for command $command. Check log $log";

	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;
	print "\n";
 
	chdir $cwd;
}

sub split_fasta
{
	my ($stage_num, $input_dir, $split_number, $log_dir) = @_;

	my $log = "$log_dir/split.log";
	my $input_file = "$input_dir/$all_fasta_name";

	print "\n=Stage $stage_num: Split Fasta=\n";
	my $begin_time = time;

	require("$script_dir/../lib/split.pl");
	print "splitting $input_file into $split_number pieces\n";
	Split::run($input_file,$split_number,$input_dir,$log);

	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;

	print "\n";
}

sub format_database
{
	my ($stage_num, $input_dir, $log_dir) = @_;

	my $log = "$log_dir/formatDatabase.log";
	my $formatdb_log = "$log_dir/formatdb.log";

	my $formatdb = $orthoParams->{'path'}->{'formatdb'};

	print "\n=Stage $stage_num: Format Database=\n";
	my $begin_time = time;

	my $database = "$input_dir/$all_fasta_name";

	my $param_keys = ['-i', '-p', '-l'];
	my $param_values = [$database, 'T', $formatdb_log];

	$job_runner->submit_job($formatdb, $param_keys, $param_values, "$log_dir/$stage_num.format-stdout.log", "$log_dir/$stage_num.format-stderr.log");

	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;
	print "\n";
}

sub perform_blast
{
	my ($stage_num, $blast_dir, $blast_results_dir, $num_tasks, $blast_log_dir) = @_;

	my $blastbin = $orthoParams->{'path'}->{'blastall'};

	my $command = $blastbin;
	my @blast_commands;
	my @blast_params_array;

	print "\n=Stage $stage_num: Perform Blast=\n";
	my $begin_time = time;

	# set autoflush
	print "performing blasts";

	# build up arrays defining jobs
	for (my $task_num = 1; $task_num <= $num_tasks; $task_num++)
	{
		my $blast_param_keys = ['-p', '-i', '-m', '-d', '-o'];
		my $blast_param_values = ['blastp', "$blast_dir/$all_fasta_name.$task_num", '8', "$blast_dir/$all_fasta_name", "$blast_results_dir/$blast_result_name.$task_num"];
		foreach my $key (keys %{$orthoParams->{'blast'}})
		{
			my $value = $orthoParams->{'blast'}->{$key};

			if (defined $value)
			{
				push(@$blast_param_keys, "-$key");
				push(@$blast_param_values, $value);
			}
		}

		push(@blast_commands,$command);
		push(@blast_params_array,{'keys' => $blast_param_keys, 'values' => $blast_param_values});
	}

	# do jobs
	$job_runner->submit_job_array(\@blast_commands,\@blast_params_array,"$blast_log_dir/$stage_num.stdout.blast","$blast_log_dir/$stage_num.stderr.blast",$num_tasks);

	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;
	print "done\n\n";
}

sub load_ortho_schema
{
	my ($stage_num, $ortho_config, $log_dir) = @_;

	print "\n=Stage $stage_num: Load OrthoMCL Database Schema=\n";
	my $begin_time = time;

	my $ortho_log = "$log_dir/orthomclSchema.log";
	
	my $orthobin = $orthoParams->{'path'}->{'orthomcl'};
	my $loadbin = "$orthobin/orthomclInstallSchema";

	my $abs_ortho_config = File::Spec->rel2abs($ortho_config);

	my $param_keys = [$abs_ortho_config, $ortho_log];
	my $param_values = [undef, undef];

	$job_runner->submit_job($loadbin, $param_keys, $param_values, "$log_dir/$stage_num.loadschema.stdout.log", "$log_dir/$stage_num.loadschema.stderr.log");

	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;
	print "\n";
}

sub parseblast
{
	my ($stage_num, $blast_results_dir, $blast_load_dir, $ortho_config, $fasta_input, $log_dir) = @_;

	my $parse_blast_log = "$log_dir/$stage_num.parseBlast.log";

	print "\n=Stage $stage_num: Parse Blast Results=\n";
	my $begin_time = time;

	my $command = "cat $blast_results_dir/$blast_result_name.* > $blast_load_dir/$blast_all_results";

	# make sure files we merge are all in sync on filesystem
	opendir(my $dh, $blast_results_dir);
	closedir($dh);
	#

	print "$command\n";
	system("$command 2> $parse_blast_log") == 0 or die "Could not concat blast results to $blast_load_dir/$blast_all_results";

	my $orthobin = $orthoParams->{'path'}->{'orthomcl'};
	my $ortho_parser = "$orthobin/orthomclBlastParser";

	my $param_keys = ["$blast_load_dir/$blast_all_results", "$fasta_input"];
	my $param_values = [undef, undef];
	$job_runner->submit_job($ortho_parser, $param_keys, $param_values, "$blast_load_dir/similarSequences.txt", $parse_blast_log);

	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;
	print "\n";
}

sub ortho_load
{
	my ($stage_num, $ortho_config, $blast_load_dir, $log_dir) = @_;

	my $ortho_log = "$log_dir/$stage_num.orthomclLoadBlast.out.log";
	my $similar_seqs = "$blast_load_dir/similarSequences.txt";

        my $orthobin = $orthoParams->{'path'}->{'orthomcl'};
        my $loadbin = "$orthobin/orthomclLoadBlast";

	print "\n=Stage $stage_num: Load Blast Results=\n";
	my $begin_time = time;

	my $abs_ortho_config = File::Spec->rel2abs($ortho_config);

	my $param_keys = ["$abs_ortho_config", "$similar_seqs"];
	my $param_values = [undef, undef];
	$job_runner->submit_job($loadbin, $param_keys, $param_values, $ortho_log, "$log_dir/$stage_num.orthomclLoadBlast.err.log");

	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;
	print "\n";
}

sub ortho_pairs
{
	my ($stage_num, $ortho_config, $log_dir) = @_;

	my $ortho_log = "$log_dir/$stage_num.orthomclPairs.log";

        my $orthobin = $orthoParams->{'path'}->{'orthomcl'};

	my $pairsbin = "$orthobin/orthomclPairs";

	print "\n=Stage $stage_num: OrthoMCL Pairs=\n";
	my $begin_time = time;

	my $abs_ortho_config = File::Spec->rel2abs($ortho_config);

	my $param_keys = ["$abs_ortho_config", "$ortho_log", "cleanup=yes"];
	my $param_values = [undef, undef, undef];

	$job_runner->submit_job($pairsbin, $param_keys, $param_values, "$ortho_log.stdout", "$ortho_log.stderr");

	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;
	print "\n";
}

sub ortho_dump_pairs
{
	my ($stage_num, $ortho_config, $pairs_dir, $log_dir) = @_;

	my $ortho_log = "$log_dir/orthomclDumpPairs.log";

        my $orthobin = $orthoParams->{'path'}->{'orthomcl'};

	my $pairsbin = "$orthobin/orthomclDumpPairsFiles";

	print "\n=Stage $stage_num: OrthoMCL Dump Pairs=\n";
	my $begin_time = time;

	my $abs_ortho_config = File::Spec->rel2abs($ortho_config);
	my $cwd = getcwd;
	chdir $pairs_dir or die "Could not change to directory $pairs_dir";

	my $command = "$pairsbin \"$abs_ortho_config\"";

	print "$command\n";
	system("$command 1>$ortho_log 2>&1") == 0 or die "Could not execute $command. See $ortho_log\n";

	chdir $cwd;

	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;
	print "\n";
}

sub run_mcl
{
	my ($stage_num, $pairs_dir, $log_dir) = @_;

	my $ortho_log = "$log_dir/$stage_num.mcl.log";
	my $mcl_input = "$pairs_dir/mclInput";
	my $mcl_output = "$pairs_dir/mclOutput";

        my $mcl_bin = $orthoParams->{'path'}->{'mcl'};
	my $mcl_inflation = $orthoParams->{'mcl'}->{'inflation'};
	if (not defined $mcl_inflation)
	{
		print STDERR "Warning: mcl inflation value not defined, defaulting to 1.5";
		$mcl_inflation = 1.5;
	}
	elsif ($mcl_inflation !~ /^\d+\.?\d*$/)
	{
		print STDERR "Warning: mcl inflation value ($mcl_inflation) is invalid, defaulting to 1.5";
		$mcl_inflation = 1.5;
	}

	print "\n=Stage $stage_num: Run MCL=\n";
	my $begin_time = time;

	my $param_keys = ["$mcl_input", '--abc', '-I', '-o'];
	my $param_values = [undef, undef, $mcl_inflation, $mcl_output];

	$job_runner->submit_job($mcl_bin, $param_keys, $param_values, "$ortho_log.stdout", "$ortho_log.stderr");

	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;
	print "\n";
}

sub mcl_to_groups
{
	my ($stage_num, $pairs_dir, $groups_dir, $log_dir) = @_;

	my $ortho_log = "$log_dir/mclGroups.log";
	my $mcl_output = "$pairs_dir/mclOutput";
	my $groups_file = "$groups_dir/groups.txt";

        my $orthobin = $orthoParams->{'path'}->{'orthomcl'};

	my $groupsbin = "$orthobin/orthomclMclToGroups";

	print "\n=Stage $stage_num: MCL to Groups=\n";
	my $begin_time = time;

	my $command = "$groupsbin group_ 1 < \"$mcl_output\" > \"$groups_file\"";

	print "$command\n";
	system("$command 2>$ortho_log") == 0 or die "Could not execute $command. See $ortho_log\n";
	print "Groups File:  $groups_file\n";

	my $end_time = time;
	printf "Stage $stage_num took %0.2f minutes \n",($end_time-$begin_time)/60;
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
my $yes_opt;
my $scheduler;

if (!GetOptions(
	'i|input-dir=s' => \$input_dir,
	'm|orthomcl-config=s' => \$orthomcl_config,
	'c|config=s' => \$main_config,
	'o|output-dir=s' => \$output_dir,
	's|split=i' => \$split_number,
	'yes' => \$yes_opt,
	'scheduler=s' => \$scheduler,
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

if (defined $yes_opt and $yes_opt)
{
	$yes = 'y';
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
    my $response = $yes || <>;
    chomp $response;
    if (not ($response eq 'y' or $response eq 'Y'))
    {
        die "Directory \"$output_dir\" already exists, could not continue.";
    }
    else
    {
        rmtree($output_dir) or die "Could not delete $output_dir before running orthomcl: $!";
	mkdir $output_dir;
    }
}
else
{
	mkdir $output_dir;
}

#override scheduler if possible
if (defined $scheduler)
{
	set_scheduler($scheduler);
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

print "Starting OrthoMCL pipeline on: ".(localtime)."\n";
my $begin_time = time;

validate_files(1, $input_dir, $compliant, $log_dir);
check_database(2, $orthomcl_config, $log_dir);
load_ortho_schema(3, $orthomcl_config, $log_dir);
if (defined $compliant && $compliant)
{
	rmtree($compliant_dir) or die "Could not delete $compliant_dir: $!";
	system("cp -R \"$input_dir\" \"$compliant_dir\"") == 0 or die "Could not copy $input_dir to $compliant_dir: $!";
}
else
{
	adjust_fasta(4, $input_dir,$compliant_dir, $log_dir);
}
filter_fasta(5, $compliant_dir,$blast_dir, $log_dir);
split_fasta(6, $blast_dir, $split_number, $log_dir);
format_database(7, $blast_dir, $log_dir);
perform_blast(8, $blast_dir, $blast_results_dir, $split_number, $blast_log_dir);
parseblast(9, $blast_results_dir, $blast_load_dir, $orthomcl_config, $compliant_dir, $log_dir);
ortho_load(10, $orthomcl_config, $blast_load_dir, $log_dir);
ortho_pairs(11, $orthomcl_config, $log_dir);
ortho_dump_pairs(12, $orthomcl_config, $pairs_dir, $log_dir);
run_mcl(13, $pairs_dir, $log_dir);
mcl_to_groups(14, $pairs_dir, $groups_dir, $log_dir);

print "Orthomcl Pipeline ended on ".(localtime)."\n";
my $end_time = time;

printf "Took %0.2f minutes to complete\n",(($end_time-$begin_time)/60);
print "Parameters used can be viewed in $orthomcl_config and $log_dir/run.properties\n";
print "Groups file can be found in $groups_dir/groups.txt\n";
