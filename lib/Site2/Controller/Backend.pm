package Site2::Controller::Backend;
use Mojo::Base 'Mojolicious::Controller';

# websocketでシグナリングする

use Mojo::JSON qw/ from_json to_json /;
use Mojo::Redis;

my $vers = {}; # 変数を集約する

sub signaling {
  my $self = shift;

     # redis setup
     $vers->{redis} ||= Mojo::Redis->new("redis://$self->app->config->{redisserver}");

     # websocket setup
     $vers->{wsid} = $self->tx->connection;
     $vers->{clients}->{$vers->{wsid}} = $self->tx;

  my $wsidsend = { "type" => "wsidnotice" , "wsid" => $vers->{wsid} };
     $vers->{clients}->{$vers->{wsid}}->send( {json => $wsidsend} );

  undef $wsidsend;

  # timeout setting
  $vers->{stream}->{$vers->{wsid}} = Mojo::IOLoop->stream($self->tx->connection);
  $vers->{stream}->{$vers->{wsid}}->timeout(60);
  $self->inactivity_timeout(60000); # 60sec

  # connection keeping 50sec
  $vers->{stream_io}->{$vers->{wsid}} = Mojo::IOLoop->recurring( 50 => sub {
		  my $self = shift;

		      my $mess = {"dummy" => "dummy" };
		      $vers->{clients}->{$vers->{wsid}}->send({json => $mess});

		  });

   # pubsub listen wsidでpubsubする
   $vers->{pubsub_cb}->{$vers->{wsid}} = $self->app->pg->pubsub->listen( "$vers->{wsid}" => sub {
		   my ($pubsub , $payload ) = @_;
		                 # $payloadはjsontext
				 my $jsonobj = from_json($payload);

		   $vers->{clients}->{$vers->{wsid}}->send({json => $jsonobj});
		   undef $jsonobj;
	   });


   # brodecast
   $vers->{pubsub_cb}->{brodecast} = $self->app->pg->pubsub->listen( 'brodecast' => sub {
		   my ($pubsub , $payload ) = @_;
		                 # $payloadはjsontext
				 my $jsonobj = from_json($payload);

		   $vers->{clients}->{$vers->{wsid}}->send({json => $jsonobj});
		   undef $jsonobj;
	   });


   # on json・・・
   $self->on(json => sub {
	my ($self, $jsonobj) = @_;

	if ( $jsonobj->{dummy} ) {
		undef $jsonobj;
            # dummy is through...
            return;
        }

	# brodecast
	if ( $jsonobj->{type} eq 'brodecast' ) {

            my $jsontext = to_json($jsonobj); #jsontextにする必要
	    $self->app->pg->pubsub->notify( 'brodecast' => $jsontext ); 	

	    undef $jsontext;

            return;
	}

	# 
	if ( $jsonobj->{to} ){

            my $jsontext = to_json($jsonobj);
	    $self->app->pg->pubsub->notify( "$jsonobj->{to}" => $jsontext );

	    undef $jsontext;

            return;
	}


   });  # on json


   # on finish
   $self->on(finish => sub {
       my ( $self, $code, $reson ) = @_;

       $self->app->pg->pubsub->unlisten( "$vers->{wsid}" => $vers->{pubsub_cb}->{$vers->{wsid}});
       $self->app->pg->pubsub->unlisten( 'brodecast' => $vers->{pubsub_cb}->{brodecast});

       Mojo::IOLoop->remove($vers->{stream_io}->{$vers->{wsid}});
       Mojo::IOLoop->remove($vers->{stream}->{$vers->{wsid}});

       delete $vers->{clients}->{$vers->{wsid}};


   }); # on finish



} # signaling

1;
