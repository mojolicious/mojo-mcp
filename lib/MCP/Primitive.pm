package MCP::Primitive;
use Mojo::Base -base, -signatures;

use MCP::Server::Context;

sub context ($self) { $self->{context} || MCP::Server::Context->new }

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

=head1 METHODS

L<MCP::Primitive> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 context

  my $context = $primitive->context;

Returns the L<MCP::Server::Context> for the current request. Capture this before an async boundary to keep using
its notification methods from later callbacks.

  # Get controller for requests using the HTTP transport
  my $c = $primitive->context->controller;

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
