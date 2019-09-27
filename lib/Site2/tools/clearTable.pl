#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use feature 'say';

# JSON型カラムのレコードを秒指定で削除する。
# 起動前に存在を確認するがテーブルの削除には対応していない。
# サーバーがUTC epochタイムを扱う前提

use Mojo::Pg;
use Time::HiRes qw( time gettimeofday tv_interval );
use DateTime;
use Mojo::JSON qw( from_json to_json );
use EV;
use AnyEvent;

$| =1;  # cache stop

my $pg = Mojo::Pg->new( 'postgresql://sitedata:sitedatapass@%2fcloudsql%2fvelvety-decoder-677:asia-east1:post1/sitedata' );

# my $pastsec = 3600;  # 3600秒経過すると削除する

my $tablelist = {
	          'walkworld' => '60',
		  'backloop' => '864000',
		  'log_tbl' => '86400',
                  };  
# checkするテーブルをリスト jsonカラムはdataであること jsonにttlカラムでエポックタイムを書き込むこと

# table構造 create table hogehoge(id bigserial NOT NULL , data jsonb);
# 出力はlog_tblにjsonで書き込む

# Table chack
sub tablechk {
    my $tables = $pg->db->tables;

    my @res;

    for my $i ( keys %$tablelist ){
        for my $j (@$tables){
            if ( $j =~ /$i/ ){ push(@res, $i); }
        # 比較内容　public.test =~ /test/ 
        } # $j
    } #$i

    my $flg;

    for my $i (keys %$tablelist){
           $flg = 0;
           for my $j (@res){
               if ($i eq $j ) { $flg = 1; }
           }
           if ($flg == 0 ) { say "$i not found!!!";  }
    }

    if ( $flg == 0 ) { exit; }

    undef $tables;
    undef $flg;
    undef @res;
} # tablechk

tablechk();

my $cv = AE::cv;
my $t = AnyEvent->timer(
        after => 0,
        interval => 60,
           cb => sub {

    for my $tbl (keys %$tablelist){

        my $t0 = time();
        my $pasttime = $t0 - $tablelist->{$tbl};
        my $tx = $pg->db->begin;   # 一括コミットで高速化
        my $dt = [ gettimeofday ];
           $pg->db->query( "DELETE from $tbl where (data->>'ttl')::numeric < $pasttime " );
           $tx->commit;
        my $log = { "PROG" => "$0" , "table" => $tbl , "ttl" => time() , "exectime" => tv_interval($dt) , "datetime" => DateTime->now , "between" => $tablelist->{$tbl}};
	my $logjson = to_json($log);
	   $pg->db->query("INSERT  INTO log_tbl(data) VALUES ( ? )" , $logjson ); 

    } # for $tbl

#   $cv->send;  # never end loop
});  # AnyEvent CV 

# TERMシグナルを受けるとメッセージを記録して終了する
my $sig = AnyEvent->signal(
	  signal => 'TERM',
	  cb => sub {

          my $mess = { "PROG" => "$0" , "ttl" => time() , "datetime" => DateTime->now , "message" => "GET signal TERM" };
	  my $messjson = to_json($mess);
	  $pg->db->query("INSERT INTO log_tbl(data) VALUES ( ? )" , $messjson );
          exit;
	  });

$cv->recv;

