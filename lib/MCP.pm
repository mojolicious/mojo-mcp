package MCP;
use Mojo::Base -base, -signatures;

our $VERSION = '0.02';

1;

=encoding utf8

=head1 NAME

MCP - Model Context Protocol Perl SDK

=head1 SYNOPSIS

  use Mojolicious::Lite -signatures;

  use MCP::Server;

  my $server = MCP::Server->new;
  $server->tool(
    name         => 'echo',
    description  => 'Echo the input text',
    input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
    code         => sub ($tool, $args) {
      return "Echo: $args->{msg}";
    }
  );

  any '/mcp' => $server->to_action;

  app->start;

=head1 DESCRIPTION

A Perl SDK for the Model Context Protocol (MCP).

=head1 SEE ALSO

L<Mojolicious>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
