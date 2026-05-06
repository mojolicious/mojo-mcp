package MCP::Primitive;
use Mojo::Base -base, -signatures;

sub context ($self) { $self->{context} || {} }

sub notify ($self, $method, $params = {}) {
  my $context = $self->context;
  return undef unless my $transport = $context->{transport};
  return $transport->notify($context->{session_id}, $method, $params);
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

=head1 METHODS

L<MCP::Primitive> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 context

  my $context = $primitive->context;

Returns the context in which the primitive is executed.

  # Get controller for requests using the HTTP transport
  my $c = $primitive->context->{controller};

=head2 notify

  my $bool = $primitive->notify($method);
  my $bool = $primitive->notify($method, {foo => 'bar'});

Send a JSON-RPC notification to the client associated with the current request context. Returns true on success, or
C<undef> if no notification could be delivered.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
