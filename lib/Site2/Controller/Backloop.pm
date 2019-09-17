package Site2::Controller::Backloop;
use Mojo::Base 'Mojolicious::Controller';

use Mojo::JSON qw( from_json to_json );
use Time::HiRes qw( time );
use Mojo::Redis;
use DateTime;

my $clients = {};
my $stream_io = {};
my $pubsub_cb = {};

sub signaling {
    my $self = shift;

    #websocket 確認
    my $wsid = $self->tx->connection;
       $self->app->log->info(sprintf 'Client connected: %s', $self->tx->connection);
       $clients->{$wsid} = $self->tx;

       # ブラウザにwsidを送信する
       my $wsidsend = { "type" => "wsidnotice" , "wsid" => $wsid };
       my $wsidjson = to_json($wsidsend);
       $clients->{$wsid}->send($wsidjson);
       undef $wsidsend;
       undef $wsidjson;

    # WebSocket接続維持設定
    #  $stream_io->{$wsid} = Mojo::IOLoop->stream($self->tx->connection);
    #   $stream_io->{$wsid}->timeout(10);   # 10sec timeout 常時接続なのですぐに切れる
       $stream_io->{$wsid} = Mojo::IOLoop->recurring( 50 => sub {
           my $loop = shift;
	   # if ($self->inactivity_timeout < 50000 ){
		  my $mess = { "dummy" => "dummy" };
		  my $messjson = to_json($mess);
                  $clients->{$wsid}->send($messjson);
		  $self->app->log->debug("DEBUG: send socket wait!!");
           #  }
	       });

          $self->inactivity_timeout(60000); #60sec   50secでdummyが送信され

    # pubsub listen
          $pubsub_cb->{$wsid} = $self->app->pg->pubsub->listen( $wsid => sub {
              my ($pubsub, $payload) = @_;

              # pubsubを受信したら自分のwebsocketに送信
              $clients->{$wsid}->send($payload);
          });

    # openchat listen
       my $cb = $self->app->pg->pubsub->listen( "openchat" => sub {
              my ($pubsub, $payload) = @_;

              # pubsubを受信したら自分のwebsocketに送信
              $clients->{$wsid}->send($payload);
          });

    # redis setup
          my $redis ||= Mojo::Redis->new("redis://10.140.0.8");

          
    # on message・・・・・・・
       $self->on(message => sub {
                  my ($self, $msg) = @_;

                  my $jsonobj = from_json($msg);
                     $self->app->log->debug("DEBUG: on session: $wsid");
                     $self->app->log->debug("DEBUG: msg: $msg");

		     $jsonobj->{from} = $wsid;

                  if ( $jsonobj->{dummy} ) {
		       $self->app->log->debug("DEBUG: pass dummy!! ");
                   # dummy pass
		       return;
                  }   

                   # server又はチャットルームへの送信
		   if ( $jsonobj->{type}) {

		         if ( $jsonobj->{type} eq "entry" ) {
		              # user情報アイコンパスが変更された場合
		              $jsonobj->{wsid} = $wsid;
		              $jsonobj->{ttl} = time();
		           my $jsontext = to_json($jsonobj);

		           my $datasec = { "data" => $jsontext };

		              $self->app->pg->db->insert("backloop", $datasec );
		              $self->app->log->debug("DEBUG: write backloop table");

		           return;
		           } # type entry
			  
			  
		   #下記のイベントを記録する (typeイベント)
		   {  
			$jsonobj->{datetime} = DateTime->now();
	             my $jsontext = to_json($jsonobj);
		     my $datasec = { "data" => $jsontext };
		        $self->app->pg->db->insert("backloop", $datasec );
	            }   


			 if ( $jsonobj->{type} eq "openchat" ) {
			     # openchatのメッセージが流れたとき
                             my $jsontxt = to_json($jsonobj);
                             $self->app->pg->pubsub->notify( "openchat" => $jsontxt );
                             return;
			 }

			 if ( $jsonobj->{type} eq "makechatroom" ) {
                             # チャットルームの作成
			    
                             my $userdata = { "user" => $jsonobj->{user} ,
                                              "icon_url" => $jsonobj->{icon_url},
                                              "wsid" => $jsonobj->{wsid},
					      "room" => $jsonobj->{roomname},
					      "pubstat" => $jsonobj->{pubstat},
				            };
			     my $userjson = to_json($userdata);

                             $redis->db->hset("ENTRY$jsonobj->{pubstat}$jsonobj->{roomname}", $jsonobj->{wsid} , $userjson);

			     return;
			 }

			 if ( $jsonobj->{type} eq "entrychatroom" ) {
                             # チャットルームへのエントリー
			   $self->app->log->info("DEBUG: entrychatroom $jsonobj->{user}"); 
                             my $userdata = { "user" => $jsonobj->{user} ,
                                              "icon_url" => $jsonobj->{icon_url},
                                              "wsid" => $jsonobj->{wsid},
					      "room" => $jsonobj->{roomname},
					      "pubstat" => $jsonobj->{pubstat}
				            };
			     my $userjson = to_json($userdata);

                             $redis->db->hset("ENTRYpublic$jsonobj->{roomname}", $jsonobj->{wsid} , $userjson);

			     my $mess = { "type" => "entrychatroomact"};
			     $clients->{$wsid}->send({ json => $mess });

			     return;
			 }

			 if ( $jsonobj->{type} eq "getlistchatroom") {
                            # チャットルームの参照

			    my $res = $redis->db->keys("ENTRYpublic*");

                            my @roomlist = ();
                            for my $key (@$res){
                            
				   $key =~ s/ENTRYpublic//;    # prefixを除去

                                push (@roomlist , $key);

			    }

			    my $roomlist = \@roomlist;

                            my $mess = { "type" => "roomlistnotice" , "chatroomlist" => $roomlist };

			    my $resjson = to_json($mess);

			    $clients->{$wsid}->send($resjson);

			    $self->app->log->debug("DEBUG: send $resjson ");

			    return;
			 }

			 if ( $jsonobj->{type} eq "getlist" ) {
                             # chatroomでメンバーを確認する

                             $self->app->log->debug("DEBUG: key: ENTRY$jsonobj->{pubstat}$jsonobj->{roomname}");

			     my $res = $redis->db->hvals("ENTRY$jsonobj->{pubstat}$jsonobj->{roomname}");

			     # $reshは配列の中身がテキストなので、バイナリに直す ブラウザ側での変換が1度で済む
			     my $resp = [];
			     for my $i (@$res){
                                 $i = from_json($i);
				 push(@$resp , $i );
			     }

			     my $mess = { "type" => "reslist" , "reslist" => $resp , "from" => $jsonobj->{from} };

			     my $memberlistjson = to_json($mess);

                                $clients->{$wsid}->send($memberlistjson);

			        $self->app->log->debug("DEBUG: send memberlist $memberlistjson");

			     return;
			 }

			 if ( $jsonobj->{type} eq "reloadmember" ){
                             #チャットのメンバーリストの再読込をメンバーに依頼する
                             my $res = $redis->db->hkeys("ENTRY$jsonobj->{pubstat}$jsonobj->{roomname}");

			     for my $i (@$res){
				 if ( $i eq $wsid ) { next ; }  # 自分は除外
				 #	 $clients->{$i}->send({ json => $jsonobj });  // websocketからpubsubに変更
				 my $jsontext = to_json($jsonobj);
				 $self->app->pg->pubsub->notify( $i => $jsontext );
				 $self->app->log->debug("DEBUG: reloadmember send $jsonobj->{roomname} $i ");
			     }

                             return;
			 }

			 if ( $jsonobj->{type} eq "chatroomchat" ) {
			     # cchatのメッセージが流れたとき
                             my $res = $redis->db->hkeys("ENTRY$jsonobj->{pubstat}$jsonobj->{roomname}");
			     my $debug = to_json($res);

			     for my $i (@$res){
                                 my $jsontxt = to_json($jsonobj);
                                 $self->app->pg->pubsub->notify( $i => $jsontxt );
				 $self->app->log->debug("DEBUG: chatroomchat send $jsonobj->{roomname} $i ");
		             } 
                             return;
			 }

			 # type call以外、order responseはsendtoで送信される
			 if ( $jsonobj->{type} eq "call" ) {
                             # webRTC用
                             my $res = $redis->db->hkeys("ENTRY$jsonobj->{pubstat}$jsonobj->{roomname}");

			     for my $i (@$res){
				 if ( $i eq $wsid ) { next ; }  # 自分は除外
				 #	 $clients->{$i}->send({ json => $jsonobj });  // websocketからpubsubに変更
				 my $jsontext = to_json($jsonobj);
				 $self->app->pg->pubsub->notify( $i => $jsontext );
				 $self->app->log->debug("DEBUG: type call send $jsonobj->{roomname} $i ");
			     }
                             return;
			 }

			 if ( $jsonobj->{type} eq "detachvoice"){
                             # hung up detachvoiceの転送
                             my $res = $redis->db->hkeys("ENTRY$jsonobj->{pubstat}$jsonobj->{roomname}");
			     my $debug = to_json($res);

			     for my $i (@$res){
                                 my $jsontxt = to_json($jsonobj);
                                 $self->app->pg->pubsub->notify( $i => $jsontxt );
				 $self->app->log->debug("DEBUG: detachvoice send $jsonobj->{roomname} $i ");
		             } 

                             return;
			 }

                         if ( $jsonobj->{type} eq "obsoleteuid" ) {
                             # chkuidからidを探して、在ると、ブラウザに削除処理を。そして、idから削除を
                             my $res = $self->app->pg->db->query("select id from obsoleteuid where data->>'olduid' = ?" , $jsonobj->{chkuid})->hash;

			     if ( ! defined $res->{id} ) {
                                 my $mess = { "type" => "resobsoleteuid" , "res" => "nonobsolete" };
				 my $messjson = to_json($mess);
                                 $clients->{$wsid}->send($messjson);
				 $self->app->log->debug("DEBUG: send nonobsolete");
                                 return;
			     } else {
                                 my $mess = { "type" => "resobsoleteuid" , "res" => "obsolete" };
				 my $messjson = to_json($mess);
                                 $clients->{$wsid}->send($messjson);
				 $self->app->log->debug("DEBUG: send obsolete");
				 $self->app->pg->db->delete('obsoleteuid' , { 'id' => $res->{id} } );
				 $self->app->log->debug("DEBUG: obsolete id: $res->{id}");
                                 return;
			     }
			 }

                         if ( $jsonobj->{type} eq "iconrotate" ){

			     my $recodetext = $self->app->pg->db->select('icondata', 'params' , { 'oid' => $jsonobj->{oid} } )->hash;
			        $self->app->log->info("DEBUG: $recodetext->{params}");
			     my $params = from_json($recodetext->{params});
			        $params->{oriented} = $jsonobj->{oriented};
			     my $paramjson = to_json($params);
                                $self->app->pg->db->update('icondata', {'params' => $paramjson }, {'oid' => $jsonobj->{oid} } );

		             my $mess = { "type" => "resiconrotate" , "oriented" => $jsonobj->{oriented} };
			     my $messjson = to_json($mess);
			        $clients->{$wsid}->send($messjson);

                             return;
			 }

			 if ($jsonobj->{type} eq "icondel" ){

			    $self->app->pg->db->delete('icondata', { "oid" => $jsonobj->{oid} } );

			    $self->app->log->info("DEBUG: delete icon data $jsonobj->{oid}");
                            return;
			 }


			 

                   # type の末尾はreternは無し  type付きのsendtoを個別送信する
	           } # if type

		   #下記のイベントを記録する (type以外) webRTCのorder responseは2重に登録されるかも
		   {  
			$jsonobj->{datetime} = DateTime->now();
	             my $jsontext = to_json($jsonobj);
		     my $datasec = { "data" => $jsontext };
		        $self->app->pg->db->insert("backloop", $datasec );
	            }   
        
                  # sendtoが含まれる場合  ブラウザ間の直接やり取りtypeを付けない個別送信
                  if ($jsonobj->{sendto}){

                      my $jsontxt = to_json($jsonobj);
                         $self->app->pg->pubsub->notify( $jsonobj->{sendto} => $jsontxt );
                         $self->app->log->debug("DEBUG: sendto: $jsonobj->{sendto} ");

		    return;
                   }



       }); # on message

    # on finish・・・・・・・
         $self->on(finish => sub{
               my ($self, $code,$reson) = @_;

	           $self->app->log->info("finish connection $wsid");

	           $self->app->pg->pubsub->unlisten($wsid => $pubsub_cb->{$wsid});
	           $self->app->pg->pubsub->unlisten("openchat" => $cb);

		   my $res = $redis->db->keys('ENTRY*'); # すべてのchatroomをチェックする
		   for my $key (@$res){
			   #  $self->app->log->info("DEBUG: key: $key");
		       my $fields = $redis->db->hkeys($key);  # fieldをチェックして一致したら削除する
		           for my $id (@$fields){
				   #  $self->app->log->info("DEBUG: id: $id");
			       if ( $wsid eq $id ) {
			           $redis->db->hdel($key , $id ); # wsidを削除する
			           $self->app->log->info("DEBUG: delete ENTRY: $key $id");
			        }
		            }
		   } # for $res   ENTRYchatrooms

		   #    $self->app->log->info("DEBUG: into websocket finish!!!");

             delete $clients->{$wsid};
	     Mojo::IOLoop->remove($stream_io->{$wsid});

       }); # on finish


} # signaling

