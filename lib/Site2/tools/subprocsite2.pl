#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use feature ':5.13';

use Proc::ProcessTable;


$|=0;

if ((! defined $ARGV[0] )||( $ARGV[0] eq "")) {
    say "subprocsite2.pl [stat , start , stop]";
    exit;
}

# 稼働プロセスのチェック

my @chklist;

my $subproclist = [ "clearTable.pl" , "npcuser_move.pl" , "trapevent.pl" , "minion-npcuser.pl" ];

sub procCheck {
    my @chklist;
    my $procs = Proc::ProcessTable->new;

#      for my $j ($procs->fields){  # fieldsリスト表示
#	    print "$j | ";
#      }
#      print "\n";
    for my $i (@{$procs->table}){
        for my $sp (@{$subproclist}){
            if (($i->{cmndline} =~ /$sp/) && ($i->{cmndline} !~ /^vi/)) {
		#  for my $j ($procs->fields){  # 全項目表示
		#    print "$i->{$j} | ";
		#}
		#print "\n";
		my $plist = { "cmndline" => $i->{cmndline} , "pid" => $i->{pid} };
		push(@chklist, $plist);
            }    
        } #$sp
    }
    return @chklist;
} # procCheck

@chklist = procCheck();

if ( $ARGV[0] eq "stat" ) {
	# スクリプト名が2個動作しているとOKとする minionは除く
	# タイミングでは再チェックが必要かもしれない
	for my $subpname (@{$subproclist}){
	    my $chkflg = 0;
	    my $flg = {};
	    if ($subpname !~ /minion/){
                for my $chk (@chklist){
                    if ($chk->{cmndline} =~ /$subpname/){
                        $chkflg++;
			$flg->{$subpname} = $chkflg;
		    }
		    #   if ($subpname =~ /npcuser_move/){ # DEBUG
		    #    print "->$chk->{cmndline}\n";
		    #}
	        } # chk
                if ($chkflg == 2 ) {
                    print "$subpname OK!\n";
		} elsif ($chkflg == 1 ) {
                    print "$subpname single process NEED CHECK!\n";
		} elsif ($chkflg == 0 ) {
                    print "$subpname NO process!\n";
		} else {
                    print "$subpname switching!\n";
		}
		$chkflg=0;
            } else {
            # minion
                for my $chk (@chklist){
                    if ($chk->{cmndline} =~ /$subpname/){
                        $chkflg++;
			$flg->{$subpname} = $chkflg;
		    }
	        }
		if ($chkflg == 1 ) {
                    print "$subpname OK!\n";
		} elsif ($chkflg == 0 ) {
                    print "$subpname NO process!\n";
		} else {
                    print "$subpname unknown!\n";
		}
                $chkflg=0;
            } # minion
	} #subpname

exit;
} # stat


if ($ARGV[0] eq "start"){
    for my $p (@{$subproclist}){
        for my $pchk (@chklist){
            if ( $pchk->{cmndline} =~ /$p/ ) {
                system("kill -TERM $pchk->{pid}");
		print "$p stoped\n";
	    }
	}	
	system("./$p > /dev/null 2>&1 &");
	print "$p start\n";
    }
exit;
} # start


if ($ARGV[0] eq "stop") {
    #動いていれば止める
    for my $p (@{$subproclist}){
        for my $pchk (@chklist){
            if ( $pchk->{cmndline} =~ /$p/ ) {
                system("kill -TERM $pchk->{pid}");
		print "$p stoped\n";
	    }
	}	
    }
exit;
} #stop

#./clearTable.pl > /dev/null 2>&1 &
#./npcuser_move.pl > /dev/null 2>&1 &
#./trapevent.pl > /dev/null 2>&1 &
#./minion-npcuser.pl minion worker > /dev/null 2>&1 &





