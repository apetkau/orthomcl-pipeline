package AutoMCL::JobManager;

use strict;
use warnings;

sub new
{
	my ($class,$script_dir) = @_;

	my $self = {};
	bless($self,$class);

	return $self;
}

sub submit_job
{
	my ($self, $command, $params_array, $stdout_log, $stderr_log) = @_;

	die "Can not execute raw JobManager";
}

sub submit_job_array
{
	my ($self, $command_array, $params_array, $stdout_log_base, $stderr_log_base) = @_;

	die "Can not execute raw JobManager";
}

sub _convert_parameters_to_array
{
	my ($self, $parameters) = @_;

	die "Can not execute raw JobManager";
}

1;
