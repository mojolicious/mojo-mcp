package MCP::Server::Transport::Stdio;
use Mojo::Base 'MCP::Server::Transport', -signatures;

use MCP::Server::Context;
use MCP::Server::Legacy qw(legacy_request);
use MCP::Server::Subscription;
use Mojo::JSON   qw(decode_json encode_json);
use Scalar::Util qw(blessed);

has subscriptions => sub { {} };

sub handle_requests ($self) {
  my $server = $self->server;

  binmode STDIN,  ':raw';
  binmode STDOUT, ':raw';
  STDOUT->autoflush(1);

  my $buffer = '';
  my $legacy = undef;
  while (defined(my $input = _read_line(\$buffer))) {
    next if $input eq '';
    my $request = eval { decode_json($input) };
    next if $self->_cancel($request);

    # Legacy
    $legacy ||= legacy_request(undef, ref $request eq 'HASH' ? $request : {});

    my $context = MCP::Server::Context->new(legacy => $legacy, stream => \&_print_response, transport => $self);
    next unless my $response = $server->handle($request, $context);

    if    (blessed($response) && $response->isa('MCP::Server::Subscription')) { $self->_subscribe($response) }
    elsif (blessed($response) && $response->isa('Mojo::Promise')) {
      $response->then(sub { _print_response($_[0]) unless $context->is_cancelled })->wait;
    }
    else { _print_response($response) }
  }
}

sub notify_all ($self, $method, $params = {}) {
  for my $subscription (values %{$self->subscriptions}) {
    next unless $subscription->wants($method);
    _print_response($subscription->notification($method, $params));
  }
  return 1;
}

sub _cancel ($self, $request) {
  return 0 unless ref $request eq 'HASH';
  return 0 unless ($request->{method} // '') eq 'notifications/cancelled';
  my $id = ($request->{params} // {})->{requestId};
  delete $self->subscriptions->{$id} if defined $id;
  return 1;
}

sub _print_response ($response) { print encode_json($response) . "\n" }

sub _read_line ($buffer) {
  while (index($$buffer, "\n") < 0) {
    last unless sysread STDIN, my $chunk, 131072;
    $$buffer .= $chunk;
  }
  return undef if $$buffer eq '';

  my $pos  = index($$buffer, "\n");
  my $line = $pos < 0 ? substr($$buffer, 0, length($$buffer), '') : substr($$buffer, 0, $pos + 1, '');
  $line =~ s/\r?\n?$//;
  return $line;
}

sub _subscribe ($self, $subscription) {
  $self->subscriptions->{$subscription->id} = $subscription;
  return _print_response($subscription->acknowledgement);
}

1;

=encoding utf8

=head1 NAME

MCP::Server::Transport::Stdio - Stdio transport for MCP servers

=head1 SYNOPSIS

  use MCP::Server::Transport::Stdio;

  my $stdio = MCP::Server::Transport::Stdio->new;

=head1 DESCRIPTION

L<MCP::Server::Transport::Stdio> is a transport for MCP (Model Context Protocol) server that reads requests from
standard input (STDIN) and writes responses to standard output (STDOUT). It is designed for command-line tools and
debugging tasks.

All messages share the one channel, so a C<subscriptions/listen> request is answered with an acknowledgement
notification and then left open, with its JSON-RPC response withheld until the client cancels it.

Requests are processed strictly in order, so a C<notifications/cancelled> notification cannot be read while the
request it refers to is still in flight; it can only cancel a subscription. Use L<MCP::Server::Transport::HTTP> for
workloads where cancelling a running tool matters.

=head1 ATTRIBUTES

L<MCP::Server::Transport::Stdio> inherits all attributes from L<MCP::Server::Transport> and implements the following
new ones.

=head2 subscriptions

  my $subscriptions = $stdio->subscriptions;
  $stdio            = $stdio->subscriptions({});

Registry of active L<MCP::Server::Subscription> objects, keyed by the id of the request that opened them.

=head1 METHODS

L<MCP::Server::Transport::Stdio> inherits all methods from L<MCP::Server::Transport> and implements the following new
ones.

=head2 handle_requests

  $stdio->handle_requests;

Reads requests from standard input and prints responses to standard output.

=head2 notify_all

  my $bool = $stdio->notify_all($method);
  my $bool = $stdio->notify_all($method, {foo => 'bar'});

Send a JSON-RPC notification to standard output, once for every subscription in L</"subscriptions"> that asked for
it.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
