#!/usr/bin/env perl
package nml_parse_orthomcl;
use strict;
use warnings;
use Pod::Usage;
use Getopt::Long;
use autodie;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use DrawVennDiagram;
use File::Basename;
__PACKAGE__->run unless caller;

#fh for ouput
our ($out_fh);


sub run {
    #grabbing arguments either from command line or from another module/script
    my ( $input, $group_file,$dir, $out,$keep_genes,$stats,$draw,$genome_list) = get_parameters(@_);
    my @group;
 
    if ( $group_file || $dir) {
    
        if ($group_file) {
            push @group,$group_file;
        }
        else {
            @group = get_files($dir);
        }

        
        foreach my $group ( @group) {
            #read in group file
            my ( $inc_genomes,$set_names) = determine_sets($group);
                        
            
            my %groups = %{ parse_orthomcl( $input, $inc_genomes,$keep_genes,$stats ) };
            
            print_results(\%groups,$set_names,$keep_genes);

            
            if ($draw ) {
                my $sets = scalar keys %$set_names;
                if ( $sets ==2 || $sets ==3  ) {
                    my $name = basename($group) . '.svg';
                    open my $out, '>' , $name;
                    my $draw = DrawVennDiagram->new('out'=>$out,'groups'=>\%groups,'labels'=>$set_names); 
                    $draw->draw();
                    close $out;        
                 }
                else {
                    print $out_fh "Can only draw venn diagram for sets of 2 or 3\n";
                }
                
            }
            
        }
    }
    elsif ( $genome_list) {
        print "Printed genomes present in your orthomcl file: $input to your '$out' outfile if given\n";
        my %genomes = %{parse_and_list_genomes($input)};
        my $number = keys %genomes;
        
        print $out_fh "Number of genomes present in your orthomcl file: $number\n";
        foreach ( keys %genomes ) {
            
            print $out_fh "$_\n";
            
        } 
        
    }
    
    return 1;
}

sub parse_and_list_genomes {
    my ($input, $genome_list) = @_;
    open my $in, '<', $input;
    my %unique_genomes;
    
    while (<$in>) {
        chomp();
        
        my ( $gid, $genes ) = split /: /;
        my @genes;
        my %genomes;
        

        foreach ( split /\s/, $genes ) {
            
            #the format 'genome_name|gene_name' is standard format coming out of orthomcl so the parse below will work for different genomes
            my ( $genome, $gene_id ) = split /\|/;
            #count and print the genomes
            $unique_genomes{$genome}++;
        }
    }
    
    close $in;
    
    return \%unique_genomes;
}

sub parse_orthomcl {
    my ( $input, $inc_genomes,$keep_genes,$stats ) = @_;
    
    open my $in, '<', $input;
    
    #hash of hash of array
    my %groups;
    my %stats;
    my $total_genes;
    my %no_group_genomes;
    
 
    while (<$in>) {
        chomp();

        my ( $gid, $genes ) = split /: /;
        my @genes;
        my %genomes;
        
        
        
        foreach ( split /\s/, $genes ) {

            #the format 'genome_name|gene_name' is standard format coming out of orthomcl so the parse below will work for different genomes
            my ( $genome, $gene_id ) = split /\|/;
           
            #check to see if we care about this genome,if not we simply ignore it
            if ( exists $inc_genomes->{$genome} ) {
                $genomes{$genome}++;

                #only keep track of all genes if required, in very large dataset keeping track of everything will take lots of memory
                if ( $stats) {
                    $total_genes++;
                    $stats{$genome}{$gene_id}=1;
                }
                push @genes, $gene_id;

            }
            else {
                $no_group_genomes{$genome}++;
            }
        }
        

        #If one or less genomes are present in the set, go to the next one
        if ( scalar keys %genomes == 0 ) {
            next;
        }


        #sort keys so we always have the same key regardless of order
        my $megakey = join( ':', sort keys %genomes );

        
        if ( exists $groups{$megakey} && $keep_genes) {
            push @{ $groups{$megakey}{'groups'} }, { 'genes' => \@genes};
        }
        else {
            $groups{$megakey}{'groups'} = [ ( { 'genes' => \@genes} ) ] if $keep_genes;
            #indicating how many genomes are in this group
            $groups{$megakey}{'num_genomes'} = scalar keys %genomes;
        }
        

        #counting number of genes fit this group
        $groups{$megakey}{'num_groups'}++;
    }
    

    close $in;


    if ( $stats) {
        print $out_fh "\n\nGenomes not included in group file:\n\n";
            
        foreach ( keys %no_group_genomes ){
            print $out_fh "$_\n";
        }
                
        print $out_fh "\nNumber of genes seen in the following genomes:\n\n";
        foreach ( keys %stats ) {
            my $num = scalar keys %{ $stats{$_}}; 
            print $out_fh "$_: $num\n";
        }
        print $out_fh "\nTotal genes seen: $total_genes\n\n";
        
    }
    

    return \%groups;

}




#one group per line
#all the possible between them
#use the groups as filtered to reduce the # of genes they are
#still can use megakey

sub determine_sets {
    my ($group) = @_;

    my (%inc_genomes,%set_names);

    open my $in, '<', $group;
    while (<$in>) {
        chomp();
        my ($tag,$data) = split /\s*:\s*/;
        die "Incorrect format for group file: '$group'\n" if !($tag) || !($data);
        die "Label cannot contain ':' character\n" if $tag =~ /:/;
        
        my @genomes = split /,/ ,$data;

        #counting # of time that the genome has been seen. Needed for error checking
        map { $inc_genomes{$_}++ } @genomes;
        
        $set_names{join( ':', sort @genomes )} = $tag;
    }
    close $in;

    
    #error checking
    #ensure that %genomes values have value of only 1,otherwise we have non unique sets
    map { $_ > 1 && die "Sets are not unique for file : '$group'"} values %inc_genomes; 

    
    return (\%inc_genomes,\%set_names);
}

sub _set_out_fh {
    my ($output) = @_;

    if ( defined $output && ref $output && ref $output eq 'GLOB' ) {
        $out_fh = $output;
    }
    elsif ( defined $output ) {
        open( $out_fh, '>', $output );
    }
    else {
        $out_fh = \*STDOUT;
    }

    return 1;
}


{

    my $group_count=1;
sub print_results {
    my ($groups,$set_names,$print_genes) = @_;
    my %groups = %{$groups};

    $group_count=1 if not $group_count;
    
    #determine order of sets based on the number of genomes in that sets
    my @ascending =
      sort { $groups{$b}{'num_genomes'} <=> $groups{$a}{'num_genomes'} }
      keys %groups;


    my $core_key = join (':', sort map { split /:/ }  keys %$set_names);
    
    #print out the Core,if it does exist
    if ( exists $groups{$core_key}) {
        print $out_fh "'Core' gene sets that is contained: "
            . $groups{ $ascending[0] }{'num_genomes'} . " genomes has "
                . $groups{ $ascending[0] }{'num_groups'}
                    . " genes\n";
    }
    else {
        print $out_fh "NO 'Core' gene sets that is contained all genomes\n";
    }

    #print out the list of sets that were identified by the user from the set file
    foreach my $megakey( keys %$set_names) {
        my $set_name = $set_names->{$megakey};
        if ( exists $groups{$megakey}) {
            print $out_fh "Found "
                . $groups{$megakey}{'num_groups'}
                    . " for the following set: $set_name\n";

            
            if ($print_genes) {
                my @genes;
                foreach (@{$groups{$megakey}{'groups'}}) {
                    my @local;
                    map { push @local,$_}  @{$_->{'genes'}};
                    push @genes, join(',',sort @local);
                }
                @genes = sort @genes;
                print $out_fh join("\n" , @genes) . "\n";
            }
            
            
        }
        else {
            print $out_fh "Found 0 for the following set: $set_name\n";
        }
        
    }

    print $out_fh "Printing out sets that were not explicit named in set file and contain at least one genome identified by user\n";

    
    
    foreach my $megakey( @ascending) {
        if ( (not exists $set_names->{$megakey}) && $core_key ne $megakey) {

            if ($print_genes) {
                open my $out,">group_$group_count" . '.csv';
                my @genes;
                foreach (@{$groups{$megakey}{'groups'}}) {
                    my @local;
                    map { push @local,$_}  @{$_->{'genes'}};
                    push @genes, join(',',sort @local);
                }
                @genes = sort @genes;
                print $out join("\n" , @genes) . "\n";
                close $out;

                print $out_fh "Found "
                    . $groups{$megakey}{'num_groups'}
                        . " in file 'group_$group_count" . '.csv' . "' for the following set: " .
                            "$megakey\n";
                
                
                $group_count++;
            }
            else {
                print $out_fh "Found "
                    . $groups{$megakey}{'num_groups'}
                        . " for the following set: " .
                            "$megakey\n";
                
            }
        }
        

        
    }

    return;
}

}


sub get_parameters {
    my ( $input, $group, $out ,$print_genes,$stats,$draw,$dir, $genome_list);
    #determine if our input are as sub arguments or getopt::long
    if ( @_ && $_[0] eq __PACKAGE__ ) {
        Getopt::Long::Configure('bundling');

        # Get command line options
        GetOptions(
            'i|input=s' => \$input,   # Orthomcl file
            'o|out=s'   => \$out,
            'g|group=s' => \$group,   #CSV of groups to determine # of orthologs
            's|stats' => \$stats,
            'd|dir=s' => \$dir,   # Directory that contains group
            'genes' => \$print_genes, #print to screen list of genes for each group
            'draw' => \$draw,
            'l|list' => \$genome_list #List genomes in orthomcl file
        );
    }
    else {
        die "NYI\n";
        
        ( $input, $group, $out ) = @_;
    }

    if ( !$input || !( -e $input ) ) {
        print "ERROR: Was not given or could not find file: '$input'\n";
        pod2usage( -verbose => 1 );
    }



    if (  ($dir && !(-d $dir) ) ) {
        print "ERROR: A directory was given but could not find it: '$dir'\n";
        pod2usage( -verbose => 1 );
    }

    if ( ($group && !(-e $group)) ) {
        print "ERROR: A group file was given but could not find it: '$group'\n";
        pod2usage( -verbose => 1 );         
    }

   
    #need at least a group file, directory or -l (for list genomes) option
    if ( !($group || $dir || $genome_list)) {
        print "ERROR: No directory or group file given. Please use -l option to print list of genomes.\n";
        pod2usage( -verbose => 1);
        
    }

    if ( $group && $genome_list || $dir && $genome_list) {
        print "\nERROR: please do not use the list (-l) option with a group file or directory!\n\n";
        
            pod2usage( -verbose =>1);
        
    }
    
    _set_out_fh($out);

    
    return ( $input, $group,$dir, $out, $print_genes,$stats,$draw, $genome_list);
}


sub get_files {
    my ($dir) =@_;
    
    opendir my ($dh), $dir;
    my @dirs = readdir $dh;
    closedir $dh;

    #removing both '.' and '..' files and putting back the full path to a list
    return  grep { ! -d $_ } map { "$dir/$_"}  grep { !/^\.\.?/} @dirs;
}

  
1;

=head1 NAME

nml_parse_orthomcl.pl - Parse orthomcl file and sort out by groups.


=head1 SYNOPSIS

     nml_parse_orthomcl.pl -i orthlist
     nml_parse_orthomcl.pl -i orthlist -o results

=head1 OPTIONS

=over

=item B<-i>, B<--input>

Orthomcl output file

=item B<-g>, B<--group>

A CSV file that contains list of groups to view their ortholog groups.

=item  B<--gene>

Prints out all ortholog sets for every group


=item B<-o> B<--out>

Output file name.

=item B<-s> B<--stats>

Print out stats about the genomes in Orthomcl

=item B<-d> B<--dir>

Give a directory that contains 'group' files. The directory needs to be given for batch submission

=item  B<--draw>

Draw a svg venn diagram file for each group file given in the current working directory. File(s) names will be same as the group file with extension 'svg'

=item B<-l> B<--list>

Print out the list of genomes in your orthomcl file

=back

=head1 DESCRIPTION


Parses the main output coming from Orthomcl into a complex data structure. The structure contains all information from the file and can be used to produce anything.

=head1 AUTHORS

Philip Mabon <philip.mabon@phac-aspc.gc.ca>

=cut
