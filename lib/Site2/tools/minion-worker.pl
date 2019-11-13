#!/usr/bin/env perl
#
# for test minion worker

use strict;
use warnings;
use utf8;
use feature 'say';

use Minion;
use Minion::Backend::Pg;
use Mojo::Pg;

my $pgmin;
my $minion;

 #  $pgmin ||= Mojo::Pg->new('postgresql://minion:minionpass@%2fcloudsql%2fvelvety-decoder-677:asia-east1:post1/minion' );
 #my $backend = Minion::Backend::Pg->new('postgresql://minion:minionpass@%2fcloudsql%2fvelvety-decoder-677:asia-east1:post1/minion' );
   $minion = Minion->new( Pg => 'postgresql://minion:minionpass@%2fcloudsql%2fvelvety-decoder-677:asia-east1:post1/minion' );

       $minion->add_task( test => sub {
           my ($job , @args) = @_;
    
           say "TEST MINION GET JOB";
       });

       $minion->add_task( procadd => sub {
           my ($job , @args) = @_;

           system("/home/debian/perlwork/mojowork/server/site2/lib/Site2/tools/npcuser_move.pl $args[0] > /dev/null 2>&1 &");
           say "add proc npcuser_move.pl $args[0] on worker";
       });

my $worker = $minion->worker;
$worker->status->{jobs} = 1;
$worker->run;
