#!/usr/bin/perl

package Devel::PartialDump;
use Moose;

use Scalar::Util qw(looks_like_number reftype blessed);

our $VERSION = "0.02";

has max_length => (
	isa => "Int",
	is  => "rw",
	predicate => "has_max_length",
	clearer => "clear_max_length",
);

has max_elements => (
	isa => "Int",
	is  => "rw",
	default => 6,
	predicate => "has_max_elements",
	clearer => "clear_max_elements",
);

has max_depth => (
	isa => "Int",
	is  => "rw",
	required => 1,
	default => 2,
);

has stringify => (
	isa => "Bool",
	is  => "rw",
	default => 0,
);

has pairs => (
	isa => "Bool",
	is  => "rw",
	default => 1,
);

sub warn {
	my ( @args ) = @_;
	my $self;

	if ( blessed($args[0]) and $args[0]->isa(__PACKAGE__) ) {
		$self = shift @args;
	} else {
		$self = our $default_dumper;
	}

	require Carp;

	Carp::carp(
		join $,,
		map {
			!ref($_) && defined($_)
				? $_
				: $self->dump($_)
		} @args
	);
}

sub dump {
	my ( @args ) = @_;
	my $self;

	if ( blessed($args[0]) and $args[0]->isa(__PACKAGE__) ) {
		$self = shift @args;
	} else {
		$self = our $default_dumper;
	}

	my $method = "dump_as_" . ( $self->should_dump_as_pairs(@args) ? "pairs" : "list" );

	my $dump = $self->$method(1, @args);

	if ( $self->has_max_length ) {
		if ( length($dump) > $self->max_length ) {
			$dump = substr($dump, 0, $self->max_length - 3) . "...";
		}
	}

	if ( not defined wantarray ) {
		CORE::warn "$dump\n";
	} else {
		return $dump;
	}
}

sub should_dump_as_pairs {
	my ( $self, @what ) = @_;

	return unless $self->pairs;

	return if @what % 2 != 0; # must be an even list

	for ( my $i = 0; $i < @what; $i += 2 ) {
		return if ref $what[$i]; # plain strings are keys
	}

	return 1;
}

sub dump_as_pairs {
	my ( $self, $depth, @what ) = @_;

	my $truncated;
	if ( $self->has_max_elements and ( @what / 2 ) > $self->max_elements ) {
		$truncated = 1;
		@what = splice(@what, 0, $self->max_elements * 2 );
	}

	return join(", ", $self->_dump_as_pairs($depth, @what), ($truncated ? "..." : ()) );
}

sub _dump_as_pairs {
	my ( $self, $depth, @what ) = @_;

	return unless @what;
	
	my ( $key, $value, @rest ) = @what;

	return (
		( $self->format_key($depth, $key) . " => " . $self->format($depth, $value) ),
		$self->_dump_as_pairs($depth, @rest),
	);
}

sub dump_as_list {
	my ( $self, $depth, @what ) = @_;

	my $truncated;
	if ( $self->has_max_elements and @what > $self->max_elements ) {
		$truncated = 1;
		@what = splice(@what, 0, $self->max_elements );
	}

	return join( ", ", ( map { $self->format($depth, $_) } @what ), ($truncated ? "..." : ()) );
}

sub format {
	my ( $self, $depth, $value ) = @_;

	defined($value)
		? ( ref($value)
			? ( blessed($value)
				? $self->format_object($depth, $value)
				: $self->format_ref($depth, $value) )
			: ( looks_like_number($value)
				? $self->format_number($depth, $value)
				: $self->format_string($depth, $value) ) )
		: $self->format_undef($depth, $value),
}

sub format_key {
	my ( $self, $depth, $key ) = @_;
	return $key;
}

sub format_ref {
	my ( $self, $depth, $ref ) = @_;

	if ( $depth > $self->max_depth ) {
		return "$ref";
	} else {
		my $reftype = reftype($ref);
		my $method = "format_" . lc reftype $ref;

		if ( $self->can($method) ) {
			$self->$method( $depth, $ref );
		} else {
			return "$ref";
		}
	}
}

sub format_array {
	my ( $self, $depth, $array ) = @_;

	return "[ " . $self->dump_as_list($depth + 1, @$array) . " ]";
}

sub format_hash {
	my ( $self, $depth, $hash ) = @_;

	return "{ " . $self->dump_as_pairs($depth + 1, %$hash) . " }";
}

sub format_scalar {
	my ( $self, $depth, $scalar ) = @_;
	return "\\" . $self->format($depth + 1, $$scalar);
}

sub format_object {
	my ( $self, $depth, $object ) = @_;
	$self->stringify ? "$object" : overload::StrVal($object)
}

sub format_string {
	my ( $self, $depth, $str ) =@_;
	# FIXME use String::Escape ?

	# remove vertical whitespace
	$str =~ s/\n/\\n/g;
	$str =~ s/\r/\\r/g;

	# reformat nonprintables
	$str =~ s/(\P{IsPrint})/"\\x{" . sprintf("%x", ord($1)) . "}"/ge;

	$self->quote($str);
}

sub quote {
	my ( $self, $str ) = @_;

	qq{"$str"};
}

sub format_undef { "undef" }

sub format_number {
	my ( $self, $depth, $value ) = @_;
	return "$value";
}

our $default_dumper = __PACKAGE__->new;

__PACKAGE__

__END__

=pod

=head1 NAME

Devel::PartialDump - Partial dumping of data structures, optimized for argument
printing.

=head1 SYNOPSIS

	use Devel::PartialDump;

	sub foo {
		print "foo called with args: " . Devel::PartialDump->new->dump(@_);
	}

=head1 DESCRIPTION

This module is a data dumper optimized for logging of arbitrary parameters.

It attempts to truncate overly verbose data, be 

=head1 ATTRIBUTES

=over 4

=item max_length

The maximum character length of the dump.

Anything bigger than this will be truncated.

Not defined by default.

=item max_elements

The maximum number of elements (array elements or pairs in a hash) to print.

Defualts to 6.

=item max_depth

The maximum level of recursion.

Defaults to 2.

=item stringify

Whether or not to let objects stringify themeslves, instead of using
L<overload/StrVal> to avoid sideffects.

Defaults to false (no overloading).

=item pairs

Whether or not to autodetect named args as pairs in the main C<dump> function.
If this attribute is true, and the top level value list is even sized, and
every odd element is not a reference, then it will dumped as pairs instead of a
list.

=back

=head1 METHODS

=over 4

=item warn

A warpper for C<dump> that prints strings plainly.

=item dump @stuff

Returns a one line, human readable, concise dump of @stuff.

=item dump_as_list $depth, @stuff

=item dump_as_pairs $depth, @stuff

Dump C<@stuff> using the various formatting functions.

Dump as pairs returns comma delimited pairs with C<< => >> between the key and the value.

Dump as list returns a comma delimited dump of the values.

=item frmat $depth, $value

=item format_key $depth, $key

=item format_object $depth, $object

=item format_ref $depth, $Ref

=item format_array $depth, $array_ref

=item format_hash $depth, $hash_ref

=item format_undef $depth, undef

=item format_string $depth, $string

=item format_number $depth, $number

=item quote $string

The various formatting methods.

You can override these to provide a custom format.

C<format_array> and C<format_hash> recurse with C<$depth + 1> into
C<dump_as_list> and C<dump_as_pairs> respectively.

C<format_ref> delegates to C<format_array> and C<format_hash> and does the
C<max_depth> tracking. It will simply stringify the ref if the recursion limit
has been reached.

=back

=head1 VERSION CONTROL

This module is maintained using Darcs. You can get the latest version from
L<http://nothingmuch.woobling.org/code>, and use C<darcs send> to commit
changes.

=head1 AUTHOR

Yuval Kogman E<lt>nothingmuch@woobling.orgE<gt>

=head1 COPYRIGHT

	Copyright (c) 2008 Yuval Kogman. All rights reserved
	This program is free software; you can redistribute
	it and/or modify it under the same terms as Perl itself.

=cut

