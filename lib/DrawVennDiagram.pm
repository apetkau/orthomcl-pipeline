package DrawVennDiagram;
# Purpose: Draws a Venn Diagram to an SVG file.
# Author: Philip Mabon <philip.mabon@phac-aspc.gc.ca>
use Moose; # automatically turns on strict and warnings
use SVG;
use Algorithm::Combinatorics qw(combinations);

has 'groups' => (is => 'rw', isa => 'HashRef');

has 'labels' => (is => 'rw', isa => 'HashRef');

has 'out' => (is => 'rw',
              isa => 'FileHandle');

sub get_order {
    my ($labels) = @_;

    my (@order,@rest);
    my $all;
    
    foreach (keys %{$labels}) {
        my $value = $labels->{$_};
        if ($value =~ /Core/ ) {
            $all =$_;
        }
        elsif (!($value =~ /:/)) {
            unshift @order,$_;
        }
        else {
            push @rest,$_;
        }
    }
    push @order, combo(@order) if (@rest);
    push @order, $all;
    
    return \@order;
}

sub combo {
    my @list;
    
    for my $i ( 0 .. $#_ ) {
        for ( my $y = $i + 1 ; $y < scalar @_ ; $y++ ) {
            my @genes = (split(/:/,$_[$i]) , split(/:/,$_[$y]));
            my $key = join (':' , sort @genes);
            push @list,$key;
        }
    }
    return @list;
}


sub fix_labels {
    my $self = shift;


    my %set_names;
    
    my $labels = $self->labels();
    
    my $sets_num = scalar keys %$labels;    
    if ($sets_num !=3  && $sets_num !=2) {
        die "Can only support groups of 2 or 3.\n";
    }


    #names of all the sets
    my @names = keys %$labels;
    
     for (my $k=1;$k <=scalar @names;$k++) {
         my @comb = combinations(\@names, $k);
        
         foreach (@comb) {
             my @genomes;

             #breakup so we have individual name for each genome so we can re-sort
             foreach my $list ( @{$_} ) {
                 map { push @genomes,$_ } split /:/,$list ;
             }
            
             my $key = join (':' , sort @genomes);

             #special label is applied to siutation where all genomes are used.
             #the reason being is if we need to identify the core , it nice to know the key ahead of time
             #instead sorting by # of genome present in every megakey
             if (scalar @names ==$k) {
                 $set_names{$key} = 'Core';
             }
             else {
                 $set_names{$key} = join ':' , map { $labels->{$_} } @{$_};
             }

         }
     }


    
    return \%set_names;
    
}


sub draw {
    my $self = shift;

    my $labels = $self->fix_labels();
    my $groups = $self->groups();
    my $out = $self->out();


    my @data;
    foreach ( @{get_order($labels)} ) {
        if ( exists $groups->{$_} ) {
            if (exists $labels->{$_}) {
                push @data, { 'label' =>$labels->{$_} ,'num' => $groups->{$_}{'num_groups'} };
            }
        }
        else {
            if (exists $labels->{$_}) {
                push @data, { 'label' =>$labels->{$_} ,'num' =>0 };
            }                
        }
    }
    
    
    my $tsize = 45;
    
    # create an SVG object
    my ( $width, $height ) = ( 2000, 1350 );
    
    
    if (scalar @data == 7) {
        ( $width, $height ) = ( 2000, 2000 );
    }

    my $svg = SVG->new( width => $width, height => $height );
    $svg->rectangle(
        x      => 1,
        y      => 1,
        width  => $width,
        height => $height,
        style  => { fill => 'white' },
        id     => 'bg'
    );

    # use explicit element constructor to generate a circles
    my $circle = $svg->group(
        id => 'groups',
        style =>
          { stroke => 'black', 'fill-opacity' => '0.0', 'stroke-width' => '4' }
    );

    my $r = $width / 3;

    my ( $left_x, $left_y ) = ( $r + 7, $height / 3 );
    $left_y = $height/2 if scalar @data == 3;
    
    my ( $right_x, $right_y ) = ( $r * 2 - 7, $height / 3 );
    $right_y = $height/2 if scalar @data == 3;

    #drawing left circle
    $circle->circle( cx => $left_x,  cy => $left_y,  r => $r, id => 'left' );

    #drawing right circle
    $circle->circle( cx => $right_x, cy => $right_y, r => $r, id => 'right' );

    #drawing 3rd (bottom) circle
    if (scalar @data ==7) {
        $circle->circle( cx => $r + $r/2 , cy => $height-$height/3 - 7, r => $r, id => 'bottom' );
    }

    
    my $text = $svg->group(
        id    => 'text',
        style => {
            'font'      => 'Arial',
            'font-size' => $tsize
        }
    );

    my @coords = ( ($r/2.5) , $left_y , ($r/2.5) , ($left_y - $tsize * 4) , #left
                   ($r * 2 + ( $r / 2.5 )), $right_y, ($r * 2 + ( $r / 2.5 )) , $right_y - $tsize * 4, #right
                   ($r + $r / 2),$left_y, ($r + $r / 2),$left_y -$tsize * 4 #middle
    );
    
    if (scalar @data ==7) {
        @coords = ( ( $r/2.5) , $left_y , ($r/2.5) , ($left_y - $tsize * 4) , #left
                    ( $r * 2 + ( $r / 2.5 )), $right_y, ($r * 2 + ( $r / 2.5 )) , $right_y - $tsize * 4, #right
                    ( $r + $r / 2 ),($left_y *2.5) , ( $r + $r / 2 ), ($left_y * 2.25), #bottom
                    ( $r + $r / 2 ),($left_y * 0.75),( $r + $r / 2 ),($left_y * 0.50), #top
                    ( $r *.9) , ($left_y * 1.75), ($r *.9), ($left_y * 1.5),# bottom left
                    ( $r*2.1) , ($left_y * 1.75), ($r*2.1) , ($left_y * 1.5),# bottom right
                    ( $r + $r / 2 ),($left_y *1.5) , ( $r + $r / 2 ),($left_y * 1.25), # middle
                );
    }


foreach (@data) {
    my ($x,$y) = ( shift @coords,shift @coords);
    $x = $x - length($_->{'num'}) * $tsize / 4;
    
    $text->text( x =>$x, y => $y, -cdata => $_->{'num'} );
    
    ($x,$y) = ( shift @coords,shift @coords);
    $x = $x - length($_->{'label'}) * $tsize / 4;
    
    $text->text( x =>$x, y => $y, -cdata => $_->{'label'} );
}
    
    # now render the SVG object, implicitly use svg namespace
    print $out $svg->xmlify;

    return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
