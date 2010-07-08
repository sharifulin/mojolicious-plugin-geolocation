#!/usr/bin/env perl
use common::sense;
use lib qw(lib /tk/lib /tk/mojo/lib); # XXX
use utf8;

use Util;
use Mojolicious::Lite;
use Data::Dumper;

my $DB = Util->db(do 'conf/mysql.conf');

plugin 'geo_location', {
	geo_ip => { db => '/usr/local/share/GeoIP/GeoLiteCity.dat' },
	geo_ip_ru => { db => { dbh => $DB, table => 'ip_geo_base_ru' } },
};

app->log->level('error');

get '/' => sub {
	my $self = shift;
	
	$self->render_json({ location => $self->stash('location') });
};

use Test::More tests => 6;
use Test::Mojo;

my $t = Test::Mojo->new;

$t->get_ok('/?ip=213.138.65.202')
	->status_is(200)
	->json_content_is({ location => {
		lat   => '47.233189',
		lon   => '39.715000',
		ip    => '213.138.65.202',
		title => 'Ростов-на-Дону, Ростовская область, Россия',
	} })
;

$t->get_ok('/?geolat=47.233189&geolong=39.715000')
	->status_is(200)
	->json_content_is({ location => {
		lat   => '47.227163',
		lon   => '39.744918',
		title => 'Ростов-на-Дону, Ростовская область, Россия',
	} })
;
