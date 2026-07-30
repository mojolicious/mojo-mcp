package MCP::Primitive;
use Mojo::Base -base, -signatures;

use Carp qw(croak);
use MCP::Server::Context;

has cache_scope => 'public';
has cache_ttl   => 0;
has scopes      => sub { [] };

sub context ($self) { $self->{context} || MCP::Server::Context->new }

sub input_required ($self, $input_requests = undef, $state = undef) {
  croak 'Input required results need input requests or state' unless $input_requests || defined $state;
  my $result = {resultType => 'input_required'};
  $result->{inputRequests} = $input_requests                    if $input_requests;
  $result->{requestState}  = $self->context->seal_state($state) if defined $state;
  return $result;
}

1;

=encoding utf8

=head1 NAME

MCP::Primitive - Primitive base class

=head1 SYNOPSIS

  package MyMCPPrimitive;
  use Mojo::Base 'MCP::Primitive';

  1;

=head1 DESCRIPTION

L<MCP::Primitive> is a base class for MCP (Model Context Protocol) primitives such as L<MCP::Tool>, L<MCP::Prompt>,
and L<MCP::Resource>.

=head1 ATTRIBUTES

L<MCP::Primitive> implements the following attributes.

=head2 cache_scope

  my $scope  = $primitive->cache_scope;
  $primitive = $primitive->cache_scope('private');

Cache scope advertised for results derived from this primitive, either C<public> for results shared by every caller,
or C<private> for results a gateway may only cache per caller. Defaults to C<public>, and is forced to C<private>
whenever L</"scopes"> is not empty.

=head2 cache_ttl

  my $ttl    = $primitive->cache_ttl;
  $primitive = $primitive->cache_ttl(60_000);

How long results derived from this primitive may be cached, in milliseconds. Defaults to C<0>, which means results
must be revalidated on every request.

=head2 scopes

  my $scopes = $primitive->scopes;
  $primitive = $primitive->scopes(['mcp:read', 'mcp:write']);

OAuth scopes required to list or call this primitive, as an array reference; all of them must be granted. This is a
local authorization policy layered on the HTTP transport's L<MCP::Server::Transport::HTTP/"auth"> hook, not wire-level
MCP metadata, and is only enforced for requests that supply scopes (so it has no effect over stdio). Defaults to no
required scopes.

=head1 METHODS

L<MCP::Primitive> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 context

  my $context = $primitive->context;

Returns the L<MCP::Server::Context> for the current request. Capture this before an async boundary to keep using
its notification methods from later callbacks.

  # Get controller for requests using the HTTP transport
  my $c = $primitive->context->controller;

=head2 input_required

  my $result = $primitive->input_required($input_requests);
  my $result = $primitive->input_required($input_requests, $state);
  my $result = $primitive->input_required(undef, $state);

Returns an C<input_required> result, asking the client to gather information and call again. At least one of the two
arguments is required.

  return $tool->input_required({
    confirm => {
      method => 'elicitation/create',
      params => {
        message         => 'Really deploy to production?',
        requestedSchema => {type => 'object', properties => {ok => {type => 'boolean'}}}
      }
    }
  }, {target => $args->{target}});

Input requests are keyed by names of your choosing, which the client mirrors back in
L<MCP::Server::Context/"input_responses">. Only ask for capabilities the client declared in
L<MCP::Server::Context/"client_capabilities">.

The optional state is any Perl data structure, and is sealed with L<MCP::Server::Context/"seal_state"> before it
travels through the client, so a retry can pick up where the first call left off without the server having to
remember anything. Read it back with L<MCP::Server::Context/"request_state">, which returns C<undef> for state that
cannot be trusted; treat that like a first call and ask again.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
