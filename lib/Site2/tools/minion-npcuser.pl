#!/usr/bin/env perl
#

use strict;
use warnings;
use utf8;
use feature 'say';

use Minion;
use Mojo::Pg;

my $minion = Minion->new( Pg => 'postgresql://minion:minionpass@%2fcloudsql%2fvelvety-decoder-677:asia-east1:post1/minion' );

   $minion->add_task( procadd => sub {
       my ($job , @args) = @_;

       system("/home/debian/perlwork/mojowork/server/site2/lib/Site2/tools/npcuser_move.pl $args[0] > /dev/null 2>&1 &");
       });

my $worker = $minion->worker;
$worker->status->{jobs} = 1;
$worker->run;
