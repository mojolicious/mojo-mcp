package Mojo::MCP::Server::Transport::Stdio;
use Mojo::Base 'Mojo::MCP::Server::Transport', -signatures;

use Mojo::JSON qw(decode_json encode_json);
use Mojo::Log;

my $log = Mojo::Log->new(path => '/Users/sri/repo/mojo-mcp/stdio.log', level => 'trace');

sub handle_requests ($self) {
  my $server = $self->server;

  STDOUT->autoflush(1);
  while (my $input = <>) {
    chomp $input;
    $log->trace("INPUT: $input");
    my $request = eval { decode_json($input) };
    next unless my $response = $server->handle($request);
    my $output = encode_json($response);
    $log->trace("OUTPUT: $output");
    print "$output\n";
  }
}

1;
