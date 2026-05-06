package MCP::Server::Session;
use Mojo::Base -base, -signatures;

has [qw(id stream)];
has last_used => sub {time};

sub touch ($self) {
  $self->last_used(time);
  return $self;
}

1;

=encoding utf8

=head1 NAME

MCP::Server::Session - Session container

=head1 SYNOPSIS

  use MCP::Server::Session;

  my $session = MCP::Server::Session->new(id => '12345');
  $session->touch;

=head1 DESCRIPTION

L<MCP::Server::Session> is a container for per-session state.

=head1 ATTRIBUTES

L<MCP::Server::Session> implements the following attributes.

=head2 id

  my $id   = $session->id;
  $session = $session->id('12345');

The session identifier.

=head2 last_used

  my $time = $session->last_used;
  $session = $session->last_used(time);

Epoch seconds of the last activity on this session, defaults to the time the session was created. Updated by
L</"touch">.

=head2 stream

  my $stream = $session->stream;
  $session   = $session->stream(Mojolicious::Controller->new);

The L<Mojolicious::Controller> currently serving the server-to-client SSE stream for this session, or C<undef> if
no stream is open.

=head1 METHODS

L<MCP::Server::Session> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 touch

  $session = $session->touch;

Set L</"last_used"> to the current time.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
