package MCP::Server::Transport;
use Mojo::Base -base, -signatures;

has 'server';

sub notifications ($self) {1}

1;

=encoding utf8

=head1 NAME

MCP:Transport - Transport base class

=head1 SYNOPSIS

  package MyMCPTransport;
  use Mojo::Base 'MCP::Server::Transport';

  1;

=head1 DESCRIPTION

L<MCP::Server::Transport> is a base class for MCP (Model Context Protocol) transport implementations.

=head1 ATTRIBUTES

L<MCP::Server::Transport> implements the following attributes.

=head2 server

  my $server = $transport->server;
  $transport = $transport->server(MCP::Server->new);

The server instance that this transport is associated with.

=head1 METHODS

L<MCP::Server::Transport> implements the following methods.

=head2 notifications

  my $bool = $transport->notifications;

True when the transport can push server-to-client notifications outside an in-flight response.

=head1 SEE ALSO

L<Mojolicious>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
