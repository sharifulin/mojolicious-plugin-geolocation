package Mojolicious::Plugin::GeoLocation;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

our $VERSION = '0.03';

=head2 TODO:
	* сделать опциональное подключение, нежесткое ~ IOLoop
	* выбор через conf, что использовать для ip и/или coder
	* выбор через conf Accept-Language
=cut

__PACKAGE__->attr(conf => sub { {} });
__PACKAGE__->attr(client => sub { Mojo::Client->new });

__PACKAGE__->attr(geo_ip => sub {
	my $self = shift;
	
	use Geo::IP;
	return Geo::IP->open($self->conf->{geo_ip}->{db}, GEOIP_STANDARD);
});

__PACKAGE__->attr(geo_ip_ru => sub {
	my $self = shift;
	
	use Geo::IP::RU::IpGeoBase;
	return Geo::IP::RU::IpGeoBase->new( db => $self->conf->{geo_ip_ru}->{db} );
});

__PACKAGE__->attr(geo_coder => sub {
	my $self = shift;
	
	use Geo::Geocoder;
	return Geo::Geocoder->new(type => 'g', api => $self->conf->{geo_coder}->{api});
});

__PACKAGE__->attr(geo_coder_ru => sub {
	my $self = shift;
	
	use Geo::Geocoder;
	return Geo::Geocoder->new(type => 'ya', api => $self->conf->{geo_coder_ru}->{api});
});

sub register {
	my ($self, $app, $conf) = @_;
	
	$self->conf( $conf );
	
	$app->plugins->add_hook(after_static_dispatch => sub {
		my ($self2, $c) = @_;
		my @ll = grep { $_ && !/^0+\.0+$/ } $c->req->param('geolat'), $c->req->param('geolong');
		
		if (@ll) {
			$self->ll( $c => [ @ll ] );
		}
		else {
			my $for = $c->req->headers->header('X-Forwarded-For');
			
			my $ip =
				$c->req->param('ip')
			 ||
				( $for && $for !~ /unknown/i ? $for : undef )
			 ||
				$c->req->headers->header('X-Real-IP')
			 ||
				$c->tx->{remote_address}
			;
			$self->ip( $c => $ip );
		}
	});
}

sub ll {
	my($self, $c, $ll) = @_;
	my $data;
	
	for my $geo (
		[ $self->geo_coder_ru, join(',', reverse @$ll), 'coder_ru' ],
		[ $self->geo_coder,    join(',',         @$ll), 'coder'    ], # XXX: с типом пока не понятно
	) {
		$self->client->get(
			$geo->[0]->url(q => $geo->[1]),
			{ 'Accept-Language' => 'ru,en-us' }, # XXX: сделать через conf
			sub {
				my($client, $tx) = @_;
				my $r = $geo->[0]->parse( $tx->res->body );
				
				$data->{ $geo->[2] } =
					[ grep { $_->{type} && $_->{type} eq 'locality' } @$r ]->[0]
				 ||
					[ grep { $_->{type} && $_->{type} eq 'province' } @$r ]->[0]
				 ||
					$r->[0]
				;
			}
		);
	}
	$self->client->process;
	
	my $l = $data->{coder_ru} || $data->{coder};
	
	$c->stash(location => $l
		? {
			lat   => $l->{ll}->[0],
			lon   => $l->{ll}->[1],
			title => join(', ', grep { $_ } @{ $l->{title}||[] }),
		}
		: undef
	);
}

sub ip {
	my($self, $c, $ip) = @_;
	my $data;
	
	if (($data) = $ip && $self->geo_ip_ru->find_by_ip( $ip )) {
		use utf8;
		
		$c->stash(location => {
			ip    => $ip,
			lat   => $data->{latitude},
			lon   => $data->{longitude},
			title => join(', ', grep { $_ }
				$data->{city} eq $data->{region} ? $data->{city} : ( @$data{qw(city region)}),
				'Россия',
			),
		});
	}
	elsif ($data = $ip && $self->geo_ip->record_by_addr( $ip )) {
		$c->stash(location => {
			ip    => $ip,
			lat   => $data->latitude,
			lon   => $data->longitude,
			title => join(', ', grep { $_ }
				$data->city,
				$data->region_name,
				grep { !/Anonymous Proxy/ } $data->country_name,
			),
		});
	}
	else {
		$c->stash(location => undef);
	}
}

1;

__END__

=head1 NAME

Mojolicious::Plugin::GeoLocation - Geo Location Mojolicious Plugin

=head1 SYNOPSIS

	plugin 'geo_location', {
		geo_ip    => { db => '/usr/local/share/GeoIP/GeoLiteCity.dat' },
		geo_ip_ru => { db => { dbh => app->db, table => 'ip_geo_base_ru' } },
		
		geo_coder    => { api => [ '..', .. ] }, # list of api key
		geo_coder_ru => { api => [ '..', .. ] }, # list of api key
	};
	
	get '/' => sub {
		my $self = shift;
		
		warn Dumper $self->stash('location'); # returns hash { lat => '..', long => '..', ip => '..', title => '..' }
	};
	
=head1 DESCRIPTION

L<Mojolicous::Plugin::GeoLocation> is a plugin to detect location, uses geolat and geolong params or IP address.

Detect geo latitude and longitude:

	$c->req->param('geolat')
	$c->req->param('geolong')

Detect IP address:

	$c->req->param('ip') ||
	$c->req->headers->header('X-Real-IP') ||
	$c->req->headers->header('X-Forwarded-For') ||
	$c->tx->{'remote_address'}

=head1 METHODS

L<Mojolicious::Plugin::GeoLocation> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

	$plugin->register;

Register plugin hooks in L<Mojolicious> application.

=head2 C<ll>

	$plugin->ll($c => [ "lat", "long" ]);

Detect location, uses geo lat and long params, based on L<Geo::Geocoder>.
First: uses Yandex geocoder (L<http://api.yandex.ru/maps/geocoder/doc/desc/concepts/reverse_geocode.xml>), second: uses Google geocoder (L<http://code.google.com/apis/maps/documentation/geocoding/>).

=head2 C<ip>

	$plugin->ip($c => $ip);

Detect location, uses IP, based on L<Geo::IP::RU::IpGeoBase> and L<Geo::IP>.
First: uses russian IP base (L<http://ipgeobase.ru>), second: uses MaxMind IP base (L<http://www.maxmind.com/>).

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

L<Geo::IP::RU::IpGeoBase>, L<Geo::IP>.

=head1 AUTHOR

Anatoly Sharifulin <sharifulin@gmail.com>

=head1 BUGS

Please report any bugs or feature requests to C<bug-mojolicious-plugin-geolocation at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.htMail?Queue=Mojolicious-Plugin-GeoLocation>.  We will be notified, and then you'll
automatically be notified of progress on your bug as we make changes.

=over 5

=item * Github

L<http://github.com/sharifulin/Mojolicious-Plugin-GeoLocation/tree/master>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.htMail?Dist=Mojolicious-Plugin-GeoLocation>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Mojolicious-Plugin-GeoLocation>

=item * CPANTS: CPAN Testing Service

L<http://cpants.perl.org/dist/overview/Mojolicious-Plugin-GeoLocation>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Mojolicious-Plugin-GeoLocation>

=item * Search CPAN

L<http://search.cpan.org/dist/Mojolicious-Plugin-GeoLocation>

=back

=head1 COPYRIGHT & LICENSE

Copyright (C) 2010 by Anatoly Sharifulin.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
