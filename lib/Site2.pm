package Site2;
use Mojo::Base 'Mojolicious';
use Mojolicious::Plugin::OAuth2;
use Mojo::Pg;

# This method will run once at server start
sub startup {
  my $self = shift;

  # hypnotoad start
  $self->config(hypnotoad=>{
                       listen => ['http://*:4200'],
                       accepts => 100000,
                       clients => 500,
                       workers => 2,
                       proxy => 1,
                       });

  # Load configuration from hash returned by config file
  my $config = $self->plugin('Config');
#  my $redisserver = $self->app->config->{redisserver};

# PG setup
     $self->app->helper ( pg =>
            sub { state $pg = Mojo::Pg->new( 'postgresql://sitedata:sitedatapass@%2fcloudsql%2fvelvety-decoder-677:asia-east1:post1/sitedata' ); # unix domain socket
         });

# $self->app->redis
#   $self->app->helper( redis =>
#        sub { state $redis ||= Mojo::Redis->new(url => "redis://$redisserver:6379");
#         });

#OAuth2
     $self->plugin('OAuth2' => {
              google => {
                  key => '861600582037-k3aos81h5fejoqokpg9mv44ghra7bvdb.apps.googleusercontent.com',
                  secret => '0pZVS18uJtj2xgvQh_84X2IP',
                  authorize_url => "https://accounts.google.com/o/oauth2/v2/auth",
                  token_url => "https://www.googleapis.com/oauth2/v4/token",
                    },
                  });


  # Configure the application
  $self->secrets($config->{secrets});

  # Router
  my $r = $self->routes;

  # Normal route to controller
#  $r->get('/')->to('example#welcome');
  $r->get('/')->to('top#top');
  $r->post('/qrcode')->to('top#qrcode');

  $r->get('/ciconimg')->to('filestore#cicon');
  $r->post('/iconupload')->to('filestore#iconupload');
  $r->get('/geticon')->to('filestore#geticon');
  $r->post('/fileupload')->to('filestore#fileupload');
  $r->get('/fileout')->to('filestore#fileout');

  $r->get('/transferuser/:uid')->to('transferuser#accept');
  $r->post('/obsoleteuid')->to('transferuser#uidobsolete');

  # test
  $r->get('/imgchk')->to('filestore#imgchk');
  $r->any('/imgout')->to('filestore#imgout');

  # websocket
  $r->websocket('/wsocket/signaling')->to(controller => 'Backloop', action => 'signaling');

  $r->any('*')->to('top#unknown');

}

1;
