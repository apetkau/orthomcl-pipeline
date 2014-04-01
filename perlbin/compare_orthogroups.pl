#!/usr/bin/env perl

use warnings;
use strict;

use Set::Scalar;
use Text::Table;
use File::Basename;

sub usage
{
	return "Usage: $0 [group1] [group2]\n".
	       "Used to compare two OrthoMCL groups files which are generated from the same data (but maybe different parameters).\n";
}

# generates sets given the passed file
# returns a Scalar::Set object containing all the orthologous groups represented as
# an alphabetically sorted string.  This should look like (for example):
# Set::Scalar:
#  'genome1|locus1 genome2|locus99'
#  'genome1|locus2 genome2|locus23'
sub generate_set
{
	my ($file) = @_;

	die "Undefined file passed" if (not defined $file);
	open(my $handle, "<$file") or die "Could not open file $file";

	my $set = Set::Scalar->new;
	while(my $line = readline($handle))
	{
		my @groups = split(/\s+/, $line);

		# remove first element (should be group id), check if '|' is not found to be sure
		shift(@groups) if ($groups[0] !~ /\|/);

		my @sorted_groups = sort {$a cmp $b} @groups;
		my $sorted_groups_string = join(' ', @groups);
		
		$set->insert($sorted_groups_string);
	}

	return $set;
}

# generates a list of sets where each set contains an individual group (genome|locus) id
# used when comparing unique differences among each group files sets.
sub generate_set_list
{
	my ($unique_set) = @_;

	die "Undefined set" if (not defined $unique_set);

	my @sets;

	for my $curr_group_string ($unique_set->elements)
	{
		my $curr_set = Set::Scalar->new;
		my @groups = split(/\s+/, $curr_group_string);

		$curr_set->insert(@groups);

		push(@sets,$curr_set);
	}

	return @sets;
}

sub print_differences
{
	my ($curr_set1, $curr_set2, $intersection, $base1, $base2) = @_;

	my @elements12;
	my @elements21;
	my @elementsint;

	if (defined $intersection)
	{
		@elementsint = $intersection->elements;
	}

	if (defined $curr_set1 and defined $curr_set2)
	{
		my $diff12 = $curr_set1->difference($curr_set2);
		my $diff21 = $curr_set2->difference($curr_set1);

		@elements12 = $diff12->elements;
		@elements21 = $diff21->elements;
	}
	elsif (defined $curr_set1)
	{
		@elements12 = $curr_set1->elements;
	}
	elsif (defined $curr_set2)
	{
		@elements21 = $curr_set2->elements;
	}
	else
	{
		die "Neither curr_set1 or curr_set2 are defined. Bad.";
	}

	print "$base1:  ";
	print "$_ " for (@elements12);
	print "===[ ";
	print "$_ " for (@elementsint);
	print "]=== ";
	print "$_ " for (@elements21);
	print " :$base2\n";
}

die usage if (@ARGV <= 0 or @ARGV > 2);

my $group1 = $ARGV[0];
my $group2 = $ARGV[1];

die "Cannot pass undefined file\n".usage if (not defined $group1);
die "Cannot pass undefined file\n".usage if (not defined $group2);
die "File $group1 does not exist" if (not -e $group1);
die "File $group2 does not exist" if (not -e $group2);

my $set1 = generate_set($group1);
my $set2 = generate_set($group2);

my $intersect = $set1->intersection($set2);
my $diff12 = $set1->difference($set2);
my $diff21 = $set2->difference($set1);


print "=== Comparison Summary ===\n\n";
my $tb = Text::Table->new('',$group1, $group2);
$tb->load(
	['Same', $intersect->size, $intersect->size],
	['Unique', $diff12->size, $diff21->size],
	['Total', $set1->size, $set2->size]
);

print $tb,"\n";

if ($diff12->size > 0 or $diff21->size > 0)
{
	print "=== Comparison of Unique Groups ===\n";
	print "Comparision in format of 'group1: unique1 ===[ intersection ]=== unique2 :group2'\n\n";

	my @unique_sets1 = generate_set_list($diff12);
	my @unique_sets2 = generate_set_list($diff21);

	my %checked_sets2 = map { $_ => $_ } @unique_sets2;
	for my $curr_set1 (@unique_sets1)
	{
		my $found = undef;
		for my $curr_set2 (@unique_sets2)
		{

			my $intersection = $curr_set1->intersection($curr_set2);
			if ($intersection->size > 0)
			{
				print "\t(also intersects with) " if (defined $found);

				$found = $curr_set2;
				print_differences($curr_set1,$curr_set2, $intersection, $group1, $group2);

				# remove from hash existence table so we don't check twice later on
				delete $checked_sets2{$curr_set2};
			}
		}

		if (not defined $found)
		{
			print_differences($curr_set1,undef, undef, $group1, $group2);
		}
	}

	# print whatever is left from set 2
	for my $curr_set2 (keys %checked_sets2)
	{
		print_differences($checked_sets2{$curr_set2},undef, undef, $group2, $group1);
	}
}
