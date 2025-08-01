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
    next unless my $response = $server->handle($request, {});

    if (blessed($response) && $response->isa('Mojo::Promise')) {
      $response->then(sub { _print_response($_[0]) })->wait;
    }
    else { _print_response($response) }
  }
}

sub _print_response ($response) { print encode_json($response) . "\n" }

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

=head1 ATTRIBUTES

L<MCP::Server::Transport::Stdio> inherits all attributes from L<MCP::Server::Transport>.

=head1 METHODS

L<MCP::Server::Transport::Stdio> inherits all methods from L<MCP::Server::Transport> and implements the following new
ones.

=head2 handle_requests

  $stdio->handle_requests;

Reads requests from standard input and prints responses to standard output.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
