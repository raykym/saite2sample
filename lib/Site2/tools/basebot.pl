#!/usr/bin/env perl
#
# open Infomationにメッセージを返す
# websocketを経由して、Backloop内で処理を行う
#
use strict;
use warnings;
use utf8;
use feature 'say';

use EV;
use Mojo::IOLoop;
use Mojo::IOLoop::Subprocess;
use Mojo::UserAgent;
use Mojo::JSON qw( from_json to_json);
use Math::Trig qw( great_circle_distance rad2deg deg2rad pi );
use AnyEvent;
use Mojo::Pg;
#use Mojo::Pg::PubSub;
use Mojo::Redis;
use Mojo::Date;
use Time::HiRes qw( time usleep gettimeofday tv_interval );
use Encode qw( encode_utf8 decode_utf8 );;
use Proc::ProcessTable;
use lib '/home/debian/perlwork/mojowork/server/site2/lib/Site2/Modules/';
use Sessionid;
#use Scalar::Util qw( weaken );
#use Devel::Cycle;


$|=1;

my $pg;
my $redis;
my $pubsub;

# 表示用ログフォーマット
sub Logging {
    my $logline = shift;
    my $logline_enc = encode_utf8($logline);
    #my $dt = DateTime->now();
    my $dt = Mojo::Date->new()->to_datetime;
    say "$dt | $logline";
       $logline = decode_utf8($logline);
    my $dblog = { 'PROG' => $0 , 'ttl' => time() , 'logline' => $logline, "dt" => $dt };
    my $dblogjson = to_json($dblog);
       $pg->db->insert('log_tbl' , { 'data' => $dblogjson } );
    
    undef $logline;
    undef $dt;
    undef $dblog;
    undef $dblogjson;

    return;
}

my $user_stat = { name => 'bot',
                  category => "USER" ,
                };

sub baseloop {
# メインループ
    my $ghostid = shift;

    my $ua = Mojo::UserAgent->new;

       $ua->connect_timeout(60);
       $ua->inactivity_timeout(60);

       $ua->websocket('wss://westwind.backbone.site/wsocket/signaling' => sub {
           my ($ua, $tx) = @_;

               say 'WebSocket handshake failed!' and return unless $tx->is_websocket;
            #  say 'Subprotocol negotiation failed!' and return unless $tx->protocol;

            sub sendmess {
		    my $obj = shift;

		       $obj->{text} = $obj->{text};

                    my $mess = { "type" => "openchat" ,
			         "user" => $user_stat->{name},
				 "text" => $obj->{text},
				 "icon_url" => "https://westwind.backbone.site/ciconimg?s=b",
			 };
		    my $messjson = to_json($mess);

                   $obj->{tx}->send($messjson);

		   undef $obj;
            }

               $tx->on(finish => sub {
                   my ($tx, $code, $reason) = @_;
                       say "WebSocket closed with status $code.";
               });

               $tx->on(json => sub {
                   my ($tx, $json) = @_;

                   Logging("on json loop start");
                   my $t0 = [gettimeofday];

                   my $jsontext = to_json($json);
                   #say "WebSocket message: $jsontext";

                   if ( $json->{dummy}) {
                        # non ope
                       return;
                   }

                   if ( $json->{type} eq "checkuser" ) {
                       my $mess = { "type" => "rescheckuser" , "res" => $user_stat->{category} };
                       my $messjson = to_json($mess);
                       $tx->send($messjson );
                       return;
                   }

                   if ($json->{type} eq "openchat" ) {

		       if ( $json->{user} eq "bot" ){
                           return;
		       }


                       if ( $json->{text} =~ /^callbot/){

			       #my @line = split($json->{text}, /?/);
                           my @line = split(// , $json->{text} );

			   my @word = splice(@line,7,$#line);
                           my $txt = join("",@word);

		           #オウム返し
                           my $obj->{text} = $txt;

		           $obj->{tx} = $tx;
			   my $txtenc = encode_utf8($txt);
			   Logging("bot say: $txtenc");

		           sendmess( $obj); 

			   undef @line;
			   undef @word;
			   undef $txt;
			   undef $obj;
			   undef $txtenc;
		        }

                    } # type openchat 

             my $elapsed = tv_interval($t0);
             my $disp = int($elapsed * 1000 );
             Logging("<=== $disp msec ===>");
             });  # $tx  json

         });   # $ua

    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

    undef $ghostid;
} # baseloop



my $childpid = -1;
my $t1;

# 基本無限ループ
while(1) {

   $pg ||= Mojo::Pg->new( 'postgresql://sitedata:sitedatapass@%2fcloudsql%2fvelvety-decoder-677:asia-east1:post1/sitedata' );

    if ( $childpid == -1 ) {
        $childpid = fork();
    } else {
	Logging("childpid no NULL");
	exit;
    }

    if ( $childpid ) {

    Logging("$0 mainprocess $$ start");

    my $cvp = AE::cv;
       $t1 = AnyEvent->timer(
        after => 3600,
        interval => 0,
           cb => sub {

           Logging("change chile process");
           system("kill -TERM $childpid");

	   $childpid = -1; #初期化

        $cvp->send;  
        });
        # TERMシグナルを受けるとメッセージを記録して終了する
        my $sig = AnyEvent->signal(
              signal => 'TERM',
              cb => sub {

              Logging("$0 process signal TERM!");
              system("kill -TERM $childpid");
              $cvp->send;  
          exit;
        });

$cvp->recv;

############################################################

    } else {
	    # childprocess

$redis ||= Mojo::Redis->new("redis://10.140.0.10");

#$pubsub ||= Mojo::Pg::PubSub->new( pg => $pg );

Logging("Child process ON");

my @loopids;

my $t0 = [gettimeofday];

my $cv = AE::cv;

# TERMシグナルを受けるとメッセージを記録して終了する
my $sig = AnyEvent->signal(
          signal => 'TERM',
          cb => sub {

              Logging("GET signal TERM");

              $cv->send;  # timer loop stop 

             });


     &baseloop();    # basebot


$cv->recv;

exit;
} # else

} # while(1)


