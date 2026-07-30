package MCP::Server::Subscription;
use Mojo::Base -base, -signatures;

use MCP::Constants qw(META_SUBSCRIPTION_ID);
use Mojo::JSON     qw(true);

use constant FILTERS => {
  'notifications/prompts/list_changed'   => 'promptsListChanged',
  'notifications/resources/list_changed' => 'resourcesListChanged',
  'notifications/tools/list_changed'     => 'toolsListChanged'
};

has 'id';
has notifications => sub { {} };
has 'stream';

sub acknowledgement ($self) {
  my $params = {_meta => {META_SUBSCRIPTION_ID() => $self->id}, notifications => $self->honoured};
  return {jsonrpc => '2.0', method => 'notifications/subscriptions/acknowledged', params => $params};
}

sub honoured ($self) {
  my $requested = $self->notifications;
  return {map { $_ => true } grep { $requested->{$_} } sort values %{(FILTERS)}};
}

sub notification ($self, $method, $params = {}) {
  my $meta = {%{$params->{_meta} // {}}, META_SUBSCRIPTION_ID() => $self->id};
  return {jsonrpc => '2.0', method => $method, params => {%$params, _meta => $meta}};
}

sub wants ($self, $method) {
  return undef unless my $key = FILTERS->{$method};
  return $self->notifications->{$key} ? 1 : 0;
}

1;

=encoding utf8

=head1 NAME

MCP::Server::Subscription - Subscription container

=head1 SYNOPSIS

  use MCP::Server::Subscription;

  my $subscription = MCP::Server::Subscription->new(id => 1, notifications => {toolsListChanged => 1});
  my $bool         = $subscription->wants('notifications/tools/list_changed');

=head1 DESCRIPTION

L<MCP::Server::Subscription> is a container for a C<subscriptions/listen> notification stream.

=head1 ATTRIBUTES

L<MCP::Server::Subscription> implements the following attributes.

=head2 id

  my $id        = $subscription->id;
  $subscription = $subscription->id(1);

The JSON-RPC id of the C<subscriptions/listen> request that opened this subscription, sent to the client as
C<_meta.io.modelcontextprotocol/subscriptionId> with every message on the stream.

=head2 notifications

  my $filter    = $subscription->notifications;
  $subscription = $subscription->notifications({toolsListChanged => 1});

The notification filter the client requested, as a hash reference. Notification types that were not requested are
never delivered.

=head2 stream

  my $stream    = $subscription->stream;
  $subscription = $subscription->stream(Mojolicious::Controller->new);

The L<Mojolicious::Controller> serving the SSE stream for this subscription, when the HTTP transport is in use.

=head1 METHODS

L<MCP::Server::Subscription> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 acknowledgement

  my $notification = $subscription->acknowledgement;

The C<notifications/subscriptions/acknowledged> notification a server has to send as the very first message on a
subscription stream, listing the notification types it will actually deliver.

=head2 honoured

  my $filter = $subscription->honoured;

The subset of L</"notifications"> the server actually supports.

=head2 notification

  my $notification = $subscription->notification($method);
  my $notification = $subscription->notification($method, {foo => 'bar'});

Build a JSON-RPC notification for this subscription, tagged with L</"id"> in
C<_meta.io.modelcontextprotocol/subscriptionId>.

=head2 wants

  my $bool = $subscription->wants('notifications/tools/list_changed');

Returns true if the given notification method was requested in L</"notifications">.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
