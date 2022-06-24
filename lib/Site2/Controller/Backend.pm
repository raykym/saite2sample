package Site2::Controller::Backend;
use Mojo::Base 'Mojolicious::Controller';

# websocketでシグナリングする
# webではなく複数のプロセスを中継する目的で

use Mojo::JSON qw/ from_json to_json /;
use Mojo::Redis;

use Math::Trig ':pi';

my $vers = {};

sub signaling {
  my $self = shift;

     # websocket setup
     my $wsid = $self->tx->connection;
     $vers->{clients}->{$wsid} = $self->tx;

  # redis setup
  state $redisserver = $self->app->config->{redisserver};
  $vers->{redis} = Mojo::Redis->new("redis://$redisserver");  # $selfとは別立て

  my $wsidsend = { "type" => "wsidnotice" , "wsid" => $wsid };
     $vers->{clients}->{$wsid}->send( {json => $wsidsend} );

  undef $wsidsend;

  # timeout setting
  $vers->{stream}->{$wsid} = Mojo::IOLoop->stream($self->tx->connection);
  $vers->{stream}->{$wsid}->timeout(60);
  $self->inactivity_timeout(60000); # 60sec

  # connection keeping 50sec -> heart beat 2sec
  $vers->{stream_io}->{$wsid} = Mojo::IOLoop->recurring( 50 => sub {
		  my $self = shift;

		      my $mess = {"dummy" => "dummy" };
		      $vers->{clients}->{$wsid}->send({json => $mess});

		  });

  # redis pubsub
  $vers->{pubsub} = $vers->{redis}->pubsub;

  $vers->{pubsub}->listen( 'brodecast' => sub {
                  my ($pubsub, $message, $channel) = @_;
		  $vers->{clients}->{$wsid}->send($message);
	  });

  $vers->{pubsub}->listen( 'bridge' => sub {
		  my ($pubsub, $message, $channel) = @_;

		  # websocketがプロセスをまたぐ場合

		  my $jsonobj = from_json($message);

		  if ( exists $vers->{clients}->{$jsonobj->{to}}) {
		      $vers->{clients}->{$jsonobj->{to}}->send($message);
		  } else {
                      return;
		  }

	  });


# サブルーチンエリア  オブジェクト化検討
    sub kmlatlng {
            my ( $lat , $lng ) = @_;
                           # 緯度によって変化する1km当たりの度数を返す
                           state $R = 6378.1; #km 
                           my $cf = cos( $lat / 180 * pi) * 2 * pi * $R; # 円周 km
                           my $kd = $cf / 360 ;  # 1度のkm
                           my $lng_km = 1 / $kd; # 軽度/1km

                           # 緯度 一定
                           state $cd = 2 * pi * $R;  # 円周 km
                           my $lat_d = $cd / 360 ;  # 1度 km
                           my $lat_km = 1 / $lat_d ; # 1km の 緯度

                           #上限値、下限値判定はパス   合わせて2kmの範囲
                           # 東経北緯の範囲のみ
                           my $lat_max = $lat + $lat_km;
                           my $lat_min = $lat - $lat_km;

                           my $lng_max = $lng + $lng_km;
                           my $lng_min = $lng - $lng_km;

                           my @return = ( $lat_min , $lat_max , $lng_min , $lng_max ) ;

                           return @return;
   }


   # on json・・・
   $self->on(json => sub {
	my ($self, $jsonobj) = @_;

	if ( $jsonobj->{dummy} ) {
		undef $jsonobj;
            # dummy is through...
            return;
        }

	# latlng entry 位置情報更新
	# unitが自分の位置情報を更新する
	# 登録情報はwsidのみでその他の情報はユニットが個別に取得する
	if ( $jsonobj->{type} eq 'entrylatlng' ){

            $self->app->redis->db->zadd('latrank' , $jsonobj->{lat}, $jsonobj->{wsid});

            $self->app->redis->db->zadd('lngrank' , $jsonobj->{lng}, $jsonobj->{wsid});

            return;
        }

	# member list request
	# unitが位置情報を送信して、見える範囲のwsidを応答する
	if ( $jsonobj->{type} eq 'wsidrequest' ){

            my ( $lat_min , $lat_max , $lng_min, $lng_max ) = &kmlatlng($jsonobj->{lat} , $jsonobj->{lng} );

            my $lats = $self->app->redis->db->zrangebyscore('latrank' , $lat_min , $lat_max );
            my $lngs = $self->app->redis->db->zrangebyscore('lngrank' , $lng_min , $lng_max );

	    my $wsidlist = {};
	    $wsidlist->{$_}++ for (@$lats , @$lngs);  # ハッシュで重複計測だけで送ってしまう

            my $mess = { type => 'wsidresponse', wsids => $wsidlist };
            #websocketではタイミングで重複送信が起きるので、pubsubでfrom宛に個別返信する
	    my $messjson = to_json($mess);
	    # pubsub 不使用で変更
	    #$self->app->pg->pubsub->notify("$jsonobj->{from}" , $messjson); 
            $vers->{clients}->{$wsid}->send($messjson);  # 自分に返る

            undef $mess;
            undef $wsidlist;
            undef $lngs;
            undef $lats;
            undef $lat_min;
            undef $lat_max;
            undef $lng_min;
            undef $lng_max;

            return;
	}
	

	# brodecast
	if ( $jsonobj->{type} eq 'brodecast' ) {

            my $jsontext = to_json($jsonobj); #jsontextにする必要
	    #$self->app->pg->pubsub->notify( 'brodecast' => $jsontext ); 	
	    $vers->{pubsub}->notify('brodecast', $jsontext );

	    undef $jsontext;

            return;
	}

	# 
	if ( $jsonobj->{to} ){

            my $jsontext = to_json($jsonobj);

                if (exists $vers->{clients}->{$jsonobj->{to}}) {

	            #$self->app->pg->pubsub->notify( "$jsonobj->{to}" => $jsontext );
	            $vers->{clients}->{$jsonobj->{to}}->send($jsontext); 
	        } else {
                    # 別プロセスへパス
                    $vers->{pubsub}->notify('bridge' , $jsontext);
		}


	    undef $jsontext;

            return;
	}


   });  # on json


   # on finish
   $self->on(finish => sub {
       my ( $self, $code, $reson ) = @_;

       $self->app->redis->db->zrem('latrank' , $wsid);
       $self->app->redis->db->zrem('lngrank' , $wsid);

       Mojo::IOLoop->remove($vers->{stream_io}->{$wsid});
       Mojo::IOLoop->remove($vers->{stream}->{$wsid});

       delete $vers->{clients}->{$wsid};

   }); # on finish



} # signaling

1;
