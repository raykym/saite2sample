package Site2::Controller::Top;
use Mojo::Base 'Mojolicious::Controller';

# 独自パスを指定して自前モジュールを利用
use lib '/home/debian/perlwork/mojowork/server/site2/lib/Site2/Modules';
use Sessionid;
use Inputchk;

use HTML::Barcode::QRCode;

use Mojo::UserAgent;


sub top {
  my $self = shift;


 # ホスト名オリジンを共有するための指定、ソースを同一にする
    $self->stash( url_orig => $self->url_for->to_abs );
 my $url_host = Mojo::URL->new($self->url_for->to_abs );
    $self->stash( url_host => $url_host->host );

  $self->render();
}

sub unknown {
    my $self = shift;
    # 未定義ページヘのアクセス
    $self->render(text => 'unknown page!!!', status => '404');
}

sub qrcode {
    my $self = shift;

    my $text = $self->param('data');
    $self->app->log->info("DEBUG: qrcode input data: $text");
  #   my $text = "test cord";
       # urlencodeのままコードにする
    if (! defined $text ){
        $self->render( text => "" );
        return ;
    }
    # site2のデザインが白黒なので、fore/backを逆転させる
    my $code = HTML::Barcode::QRCode->new(text => $text, foreground_color => '#ffffff' , background_color => '#000000');

    $self->app->log->info("qrcode: $text");

    $self->render( text => $code->render );
}

sub explain {
    my $self = shift;

    $self->render();
}

sub adminhook {
    my $self = shift;

    my $param = $self->param("p");
    if ( !defined $param ){
        $self->render( text => "error on" );
        return;
    }

    my $ua = Mojo::UserAgent->new;

    $ua->post("https://maker.ifttt.com/trigger/webhook/with/key/8oVxZGi0ZloYzuJZc-kfI");

    $self->render( text => "" );
}

1;
