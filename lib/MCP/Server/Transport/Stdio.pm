package MCP::Server::Transport::Stdio;
use Mojo::Base 'MCP::Server::Transport', -signatures;

use Mojo::JSON qw(decode_json encode_json);
use Mojo::Log;
use Scalar::Util qw(blessed);

sub handle_requests ($self) {
  my $server = $self->server;

  STDOUT->autoflush(1);
  while (my $input = <>) {
    chomp $input;
    my $request = eval { decode_json($input) };
    next unless my $response = $server->handle($request);

    if (blessed($response) && $response->isa('Mojo::Promise')) {
      $response->then(sub { _print_response($_[0]) })->wait;
    }
    else { _print_response($response) }
  }
}

sub _print_response ($response) { print encode_json($response) . "\n" }

1;
