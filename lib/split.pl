#!/usr/bin/perl

package Split;

use strict;

use Getopt::Long;
use File::Basename qw(basename);
use Bio::SeqIO;

__PACKAGE__->run() unless caller;

1;

sub usage
{
    print "Usage: split.pl -i <fasta file> -n <split number> [-o <output dir>] [-l <log file>]\n";
}

sub run
{
    my ($file,$split,$output_dir,$log_file);
    open(my $out_fh, '>-') or die "Could not open stdout for writing";

    if ( @_ && $_[0] eq __PACKAGE__)
    {
        GetOptions('i|input-file=s' => \$file,
                   'o|output-dir=s' => \$output_dir,
                   'n|split-number=i' => \$split,
                   'l|log-file=s' => \$log_file) or die "Invalid options\n";
    }
    else
    {
        ($file,$split,$output_dir,$log_file) = @_;
    }

    if (defined $log_file)
    {
        open($out_fh, '>', $log_file) or die "Could not open $log_file: $!";
    }
    
    die usage unless $split && $file;
    die "File $file does not exist\n" unless -e $file;
    
    #this will find records with a quickness
    (my $total) = `grep -c ">" $file`;
    chomp $total;
    print $out_fh "$total records into $split files\n";
    die "no fasta records identified, exiting.\n" unless $total;
    
    my $records_per_file = int ($total / $split);
    my $leftover_records = $total % $split;
    
    if ($split > $total) {
       warn "Total records in file ($total) less than splitnum ($split); adjusting toatal\n";
       $records_per_file = 1;
    }
    
    my $input_file_name = basename($file);
    my $output_base_path = (defined $output_dir) ? "$output_dir/$input_file_name" : $input_file_name;
    my $in = new Bio::SeqIO (-file=>$file, -format=>"fasta");
    my $x;
    my @outs;
    my $records;
    for my $x (1..$split) { 
      #adjust # of records per file for leftover records
      my $adjusted_records_per_file; 
      $adjusted_records_per_file = $records_per_file+1 if $x <= $leftover_records;
      push @outs, new Bio::SeqIO (-file=>">$output_base_path.$x", -format=>"fasta")
    }
    
    my $out = shift @outs;
    my $filecounter = 1;
    my $recordcounter =1;
    while (my $seq = $in->next_seq) {
      print $out_fh $recordcounter++,"\t", $seq->display_id,"\n";
      my $adjusted_records_per_file = $filecounter<=$leftover_records?$records_per_file+1:$records_per_file;
      $out->write_seq($seq);
      if (++$records>=$adjusted_records_per_file) {
        $out = shift @outs; $records =0; $filecounter++;   
      }
    }
}
