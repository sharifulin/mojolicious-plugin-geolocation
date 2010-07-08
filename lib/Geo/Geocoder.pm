package Geo::Geocoder;

use strict;
use warnings;

use JSON;
use Encode ();

our $VERSION = '0.03';

our $API  = {
	g  => [
		'ABQIAAAAnOegvMJPx8wF5TWZVKrBeRQ32X4_GyVBxRJBsc3rUDXyCgRITRTzL_1hVt57cyThBwOf_UAoJA1QSw',
		'ABQIAAAAnOegvMJPx8wF5TWZVKrBeRR1jWpFYN4hL5FbEvjoxo6eG5GZ8xQJSMJ-CXZiu14d1864GTWPHDMhqw',
		'ABQIAAAAUFsaE9QbGTT6bzUai8kf0RQI8JRKGenwZi0XZK8nWImClxJIVBRGZTZmJUQ93JvYTy4TDQRJTj8_KQ',
	],
	ya => [
		'ANpUFEkBAAAAf7jmJwMAHGZHrcKNDsbEqEVjEUtCmufxQMwAAAAAAAAAAAAvVrubVT4btztbduoIgTLAeFILaQ==',
		'AIXxG0oBAAAAtSbBCgIAJhmfRrUGPepxWcv9Ij25xb0wXQEAAAAAAAAAAAACt24kzDKWCx0zPD7RJlhsA4FqJg==',
		'AAsjJEkBAAAAfEfSfQIAhhRrDMibjyfY_8DoKEgYacKozjcAAAAAAAAAAAB9Hgazx_NPMysN-PTucVtml8mmLw==',
		'APk-JUkBAAAAMsWKVQIAELu6JAFGPsiNKzLRXN5pfZJ7GG0AAAAAAAAAAAChD-n4LhH-5xYMH39yvhvE7o-PRw==',
		'AHcR2kkBAAAAorz_NAMAAgxMTSrrahcECBia5FYzUPcdNqAAAAAAAAAAAABkQhyAI34ZQqpEpFRPnahHByjyxg==',
		'AHcR2kkBAAAAorz_NAMAAgxMTSrrahcECBia5FYzUPcdNqAAAAAAAAAAAABkQhyAI34ZQqpEpFRPnahHByjyxg==',
		'AIUtxUkBAAAAyve0SQIAhfrGFFO3_jynNI1YrBdNLQdkIWIAAAAAAAAAAAAFnyDDTMCSU3ULFOZTuydW0ekuiQ==',
		'AHJBLkoBAAAAGqe9ZwIAhOe8yYftuyA8MJH2Hekr_WPhOr4AAAAAAAAAAAAvvJ8UIHh5yWcrOqQSrpJkjjz91w==',
		'ABbBmkkBAAAAlcMXLQMAA0RBDpqm2GdvCm6D7V9ptniwS7gAAAAAAAAAAAAR18v5TJHs0KhnSY3KjEbV-yxN7g==',
		'AIMoFUoBAAAAXXqCeQIAa2HWh99Pzf1o-20Bu_3d-jOXYeYAAAAAAAAAAABogmzTCqjTs7Za_P7IPJVE8Qlpfw==',
		'AGJn1EkBAAAAlgndawIAB0xYVEd5ZfPUplkx2BYmsg7X1oIAAAAAAAAAAACfsZmfIRpH2ovajVywBkgXgwE4sg==',
		'APec3kkBAAAAQIqCewIA4Q4WQQ3MMjD1jE51LKhZbjsFtcoAAAAAAAAAAAB6JDpQr60HjcGxPlzQezAq54Fu-Q==',
	],
};

our $TYPE = {
	g  => {
		url   => 'http://maps.google.com/maps/geo',
		q     => 'q',
		p     => 'output=json&oe=utf8&sensor=false', # gl=4
		
		parse => sub {
			my $raw  = shift;
			my $json = decode_json( $raw );
			
			use utf8;
			
			return [
				map  {
					my $address = $_->{'address'}; $address =~ s/город //; # FIX
					# XXX: http://maps.google.com/maps/geo?q=55.768883,37.515968&output=json&oe=utf8&sensor=false&key=ABQIAAAAUFsaE9QbGTT6bzUai8kf0RQI8JRKGenwZi0XZK8nWImClxJIVBRGZTZmJUQ93JvYTy4TDQRJTj8_KQ
					
					+{
						text  => $address,
						title => [ split /\s*,\s*/, $address ],
						type  => {
							4 => 'locality', 2 => 'province', 1 => 'country', 0 => 'area', 3 => 'area',
						}->{ $_->{'AddressDetails'}->{'Accuracy'} },
						ll    => [ @{$_->{'Point'}->{'coordinates'}||[]}[1,0] ],
					};
				}
				@{ $json->{'Placemark'}||[] }
			];
		},
	},
	ya => {
		url   => 'http://geocode-maps.yandex.ru/1.x/',
		q     => 'geocode',
		p     => 'results=30', # limit
		
		parse => sub {
			my $raw = shift;
			return [
				map  {
					my $d  = [ m{<kind>([^<]+).*?<text>([^<]+)}s ];
					
					Encode::_utf8_on($d->[1]);
					
					+{
						text  => $d->[1],
						title => [ reverse split /\s*,\s*/, $d->[1] ],
						type  => $d->[0],
						ll    => [ reverse map { split / / } m{<pos>([^<]+)} ],
					};
				}
				$raw =~ m{<featureMember(.*?)feature}sg
			];
		},
	},
};

sub new {
	shift;
	return bless {@_}, __PACKAGE__;
}

sub url {
	my $self = shift;
	my $p    = {@_};
	
	my $type = $TYPE->{ $self->{type} };
	my $api  = $p->{'api'} || $API->{ $self->{type} };
	
	return join '?',
		$type->{url},
		join '&',
			$type->{q} .'='. $p->{q},
			$type->{p},
			
			(map { $p->{$_} ? "$_=" . join(',', reverse @{$p->{$_}}) : () } 'll', 'spn'),
			
			ref $api ? 'key=' . $api->[rand @$api] : "key=$api",
	;
}

sub parse {
	my $self = shift;
	return $TYPE->{ $self->{type} }->{parse}->(@_);
}

1;
