#!/usr/bin/perl

package AutoMCL::JobManager::Fork;

use strict;
use warnings;

use AutoMCL::JobManager;
our @ISA = qw(AutoMCL::JobManager);

use Parallel::ForkManager;

sub new
{
	my ($proto,$script_dir) = @_;

	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new($script_dir);
	bless($self,$class);

	return $self;
}

# submits passed job using array ref of parameters, and the passed log files
# please use full paths for all files
sub submit_job
{
        my ($self, $command, $param_keys, $param_values, $stdout_log, $stderr_log) = @_;

        die "Error: undefined command" if (not defined $command);
        die "Error: command $command does not exist" if (not -e $command);
        die "Error: undefined stdout log" if (not defined $stdout_log);
        die "Error: undefined stderr log" if (not defined $stderr_log);

	my $params_array = $self->_convert_parameters_to_array($param_keys, $param_values);

	my $command_string = $command.' '.join(' ',@$params_array)." 1>$stdout_log 2>$stderr_log";
	print "$command_string\n";

	system($command_string) == 0 or die "Error executing command: $command_string. See logs $stdout_log and $stderr_log\n";
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
	
	my $child_p_group;
	my $forker = new Parallel::ForkManager($max_threads);
	$forker->run_on_finish(
		sub {
			my ($pid, $exit_code, $ident) = @_;
			if ($exit_code != 0)
			{
				print STDERR "Error: job failed for child (pid=$pid, ident=$ident) with exit code ($exit_code).\nKilling children (process group $child_p_group)\n";
				kill -15,$child_p_group;
				die;
			}
		}
	);

	for (my $id = 0; $id < $command_size; $id++)
	{
		my $pid = $forker->start($id);

		if ($pid) # if parent
		{
			$child_p_group = getpgrp $pid;
		}
		else
		{
			# in child
			my $command = $command_array->[$id];
			my $params = $self->_convert_parameters_to_array($params_array->[$id]->{'keys'},
									 $params_array->[$id]->{'values'});
	
			die "Error: command not defined for iteration $id" if (not defined $command);
	
			my $command_string = $command;
			if (defined $params)
			{
				die "Error: params not an array reference for iteration $id" if (not (ref $params eq 'ARRAY'));
	
				$command_string .= ' '.join(' ',@$params);
			}
			$command_string .= " 1>$stdout_log_base.".($id+1)." 2>$stderr_log_base.".($id+1);
	
			print "executing $command_string\n";
			my $exit_value = system($command_string);
	
			$forker->finish($exit_value);
		}
	}
	$forker->wait_all_children;
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

	for(my $i = 0; $i < scalar(@$param_keys); $i++)
	{
		my $key = $param_keys->[$i];
		my $value = $param_values->[$i];

		if (defined $value)
		{
			push(@$params_array, $key);
			push(@$params_array, "\"$value\"");
		}
		else
		{
			push(@$params_array, "\"$key\"");
		}
	}

	return $params_array;
}

1;
