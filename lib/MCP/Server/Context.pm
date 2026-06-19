package MCP::Server::Context;
use Mojo::Base -base, -signatures;

has [qw(controller insufficient_scope progress_token session_id transport)];
has scopes => sub { [] };

sub has_scope ($self, @needed) {
  my %granted = map { $_ => 1 } @{$self->scopes};
  for my $scope (@needed) { return 0 unless $granted{$scope} }
  return 1;
}

sub notify ($self, $method, $params = {}) {
  return undef unless my $transport = $self->transport;
  return $transport->notify($self->session_id, $method, $params);
}

sub notify_progress ($self, $progress, $total = undef, $message = undef) {
  return undef unless defined(my $token = $self->progress_token);
  my $params = {progressToken => $token, progress => $progress};
  $params->{total}   = $total   if defined $total;
  $params->{message} = $message if defined $message;
  return $self->notify('notifications/progress', $params);
}

1;

=encoding utf8

=head1 NAME

MCP::Server::Context - Request context container

=head1 SYNOPSIS

  use MCP::Server::Context;

  my $context = MCP::Server::Context->new;
  $context->notify_progress(1, 2, 'halfway');

=head1 DESCRIPTION

L<MCP::Server::Context> is a container for per-invocation request context.

=head1 ATTRIBUTES

L<MCP::Server::Context> implements the following attributes.

=head2 controller

  my $c    = $context->controller;
  $context = $context->controller(Mojolicious::Controller->new);

The L<Mojolicious::Controller> serving the current request, when the HTTP transport is in use.

=head2 insufficient_scope

  my $needed = $context->insufficient_scope;
  $context   = $context->insufficient_scope(['mcp:write']);

Array reference of scopes a denied request was missing, set by the server so the HTTP transport can emit an
C<insufficient_scope> challenge. C<undef> when no scope check failed.

=head2 progress_token

  my $token = $context->progress_token;
  $context  = $context->progress_token('tok-1');

The progress token provided by the client in C<_meta.progressToken>, or C<undef> if none was sent.

=head2 session_id

  my $id   = $context->session_id;
  $context = $context->session_id('12345');

Identifier of the session this request belongs to.

=head2 scopes

  my $scopes = $context->scopes;
  $context   = $context->scopes(['mcp:read', 'mcp:write']);

OAuth scopes granted to the current request, as an array reference, populated from the C<auth> hook of the HTTP
transport. Defaults to an empty array reference.

=head2 transport

  my $transport = $context->transport;
  $context      = $context->transport(MCP::Server::Transport::HTTP->new);

The transport handling the current request.

=head1 METHODS

L<MCP::Server::Context> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 has_scope

  my $bool = $context->has_scope('mcp:write');
  my $bool = $context->has_scope('mcp:read', 'mcp:write');

Returns true if every given scope is present in L</"scopes">.

=head2 notify

  my $bool = $context->notify($method);
  my $bool = $context->notify($method, {foo => 'bar'});

Send a JSON-RPC notification to the client associated with the current request. Returns true on success, or
C<undef> if no notification could be delivered.

=head2 notify_progress

  my $bool = $context->notify_progress($progress);
  my $bool = $context->notify_progress($progress, $total);
  my $bool = $context->notify_progress($progress, $total, $message);

Send a C<notifications/progress> JSON-RPC notification for the progress token associated with the current request.
Returns true on success, or C<undef> if no progress token was provided by the client.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
