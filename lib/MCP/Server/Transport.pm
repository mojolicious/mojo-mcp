package MCP::Server::Transport;
use Mojo::Base -base, -signatures;

has 'server';

1;

=encoding utf8

=head1 NAME

MCP:Transport - Transport base class

=head1 SYNOPSIS

  package MyMCPTransport;
  use Mojo::Base 'MCP::Server::Transport';

  1;

=head1 DESCRIPTION

L<MCP::Server::Transport> is a base class for Model Context Protocol (MCP) transport implementations.

=head1 ATTRIBUTES

L<MCP::Server::Transport> implements the following attributes.

=head2 server

  my $server = $transport->server;
  $transport = $transport->server(MCP::Server->new);

The server instance that this transport is associated with.

=head1 SEE ALSO

L<Mojolicious>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
