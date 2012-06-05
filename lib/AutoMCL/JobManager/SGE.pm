#!/usr/bin/perl

package AutoMCL::JobManager::SGE;

use strict;
use warnings;

use AutoMCL::JobManager;
our @ISA = qw(AutoMCL::JobManager);

use Schedule::DRMAAc qw( :all );

sub new
{
	my ($proto,$script_dir) = @_;

	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new($script_dir);
	bless($self,$class);

	return $self;
}

sub _start_scheduler
{
        my ($self, $drmerr, $drmdiag) = drmaa_init(undef);
        die drmaa_strerror($drmerr),"\n",$drmdiag if ($drmerr);
}

sub _stop_scheduler
{
        my ($self, $drmerr,$drmdiag) = drmaa_exit();
        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;
}

# submits passed job using hash ref of parameters, and the passed log files
# please use full paths for all files that are accessible on all cluster nodes
sub submit_job
{
        my ($self, $command, $param_keys, $param_values, $stdout_log, $stderr_log) = @_;

        die "Error: undefined command" if (not defined $command);
        die "Error: command $command does not exist" if (not -e $command);
        die "Error: undefined stdout log" if (not defined $stdout_log);
        die "Error: undefined stderr log" if (not defined $stderr_log);

        my $task_num = 0;
        my @job_ids;

	my $params_array = $self->_convert_parameters_to_array($param_keys, $param_values);

	print "$command ".join(' ',@$params_array)."\n";

        # set autoflush
        $| = 1;
        $self->_start_scheduler();

        my ($drmerr,$jt,$drmdiag,$jobid,$drmps);

        ($drmerr,$jt,$drmdiag) = drmaa_allocate_job_template();
        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;

        ($drmerr,$drmdiag) = drmaa_set_attribute($jt,$DRMAA_REMOTE_COMMAND,$command); #sets the command for the job to be run
        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;

        ($drmerr,$drmdiag) = drmaa_set_attribute($jt,$DRMAA_OUTPUT_PATH,":$stdout_log"); #sets the output directory for stdout
        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;

        ($drmerr,$drmdiag) = drmaa_set_attribute($jt,$DRMAA_ERROR_PATH,":$stderr_log"); #sets the output directory for stdout
        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;

        ($drmerr,$drmdiag) = drmaa_set_vector_attribute($jt,$DRMAA_V_ARGV,$params_array); #sets the list of arguments to be applied to this job
        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;

        ($drmerr,$jobid,$drmdiag) = drmaa_run_job($jt); #submits the job to whatever scheduler you're using
        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;

        ($drmerr,$drmdiag) = drmaa_delete_job_template($jt); #clears up the template for this job
        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;

        push(@job_ids,$jobid);

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

        $self->_stop_scheduler();
}

sub submit_job_array
{
	my ($self, $command_array, $params_array, $stdout_log_base, $stderr_log_base, $max_threads) = @_;

        die "Error: undefined command" if (not defined $command_array);
        die "Error: command not an array reference does not exist" if (not (ref $command_array eq 'ARRAY'));
        die "Error: undefined stdout log base" if (not defined $stdout_log_base);
        die "Error: undefined stderr log base" if (not defined $stderr_log_base);
        die "Error: max_threads not defined" if (not defined $max_threads);
        die "Error: max_threads=$max_threads not valid integer" if ($max_threads !~ /^\d+$/);
        die "Error: max_threads is 0" if ($max_threads eq 0);

	my $command_size = scalar(@$command_array);
        if (defined $params_array)
        {
                die "Error: params defined but not an array reference" if (not (ref $params_array eq 'ARRAY'));

                my $params_size = scalar(@$params_array);
                die "Error: command_array ($command_size) and params_array ($params_size) aren't same size" if ($command_size ne $params_size);
        }

	my @job_ids;

	# set autoflush
	$| = 1;
	$self->_start_scheduler();

        my ($drmerr,$jt,$drmdiag,$jobid,$drmps);

	for (my $id = 0; $id < $command_size; $id++)
	{
		my $task_num = $id+1;

		my $curr_command = $command_array->[$id];
		my $curr_params = $self->_convert_parameters_to_array($params_array->[$id]->{'keys'},
								      $params_array->[$id]->{'values'});
		print "$curr_command ".join(' ',@$curr_params)."\n";

        	($drmerr,$jt,$drmdiag) = drmaa_allocate_job_template();
		die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;

		($drmerr,$drmdiag) = drmaa_set_attribute($jt,$DRMAA_REMOTE_COMMAND,$curr_command); #sets the command for the job to be run
		die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;

		($drmerr,$drmdiag) = drmaa_set_attribute($jt,$DRMAA_OUTPUT_PATH,":${stdout_log_base}.$task_num"); #sets the output directory for stdout
	        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;
	
		($drmerr,$drmdiag) = drmaa_set_attribute($jt,$DRMAA_ERROR_PATH,":${stderr_log_base}.$task_num"); #sets the output directory for stdout
	        die drmaa_strerror($drmerr)."\n".$drmdiag if $drmerr;
	
		($drmerr,$drmdiag) = drmaa_set_vector_attribute($jt,$DRMAA_V_ARGV,$curr_params); #sets the list of arguments to be applied to this job
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

	$self->_stop_scheduler();
}

sub _convert_parameters_to_array
{
        my ($self, $param_keys, $param_values) = @_;

        die "Error: param_keys is undefined" if (not defined $param_keys);
        die "Error: param_values is undefined" if (not defined $param_values);
        die "Error: param_keys not array ref" if (not (ref $param_keys eq 'ARRAY'));
        die "Error: param_values not array ref" if (not (ref $param_values eq 'ARRAY'));
        die "Error: parameter arrays not same size" if (scalar(@$param_keys) ne scalar(@$param_values));

        my $params_array = [];

	for (my $i = 0; $i < scalar(@$param_keys); $i++)
        {
		my $key = $param_keys->[$i];
                my $value = $param_values->[$i];

		if (defined $value)
		{
                	push(@$params_array, "$key");
	                push(@$params_array, "$value");
		}
		else
		{
			push(@$params_array, $key);
		}
        }

        return $params_array;
}

1;
