package MCP::Server::Legacy;
use Mojo::Base 'Exporter', -signatures;

use MCP::Constants qw(LEGACY_VERSION META_PROTOCOL_VERSION);

our @EXPORT_OK = qw(legacy_context legacy_request legacy_result);

sub legacy_context ($params, $context) {
  my $meta = $params->{_meta} // {};
  $context->client_capabilities({})->client_info({})->protocol_version(LEGACY_VERSION);
  $context->progress_token($meta->{progressToken}) if defined $meta->{progressToken};
  return $context;
}

sub legacy_request ($version, $request) {
  return 1 if ($request->{method} // '') eq 'initialize';
  return 0 unless defined $version && $version eq LEGACY_VERSION;
  return ($request->{params} // {})->{_meta}{+META_PROTOCOL_VERSION} ? 0 : 1;
}

sub legacy_result ($server, $method) {
  return {} if $method eq 'ping';
  return undef unless $method eq 'initialize';
  return {
    protocolVersion => LEGACY_VERSION,
    capabilities    => {prompts => {}, resources => {}, tools => {}},
    serverInfo      => {name    => $server->name, version => $server->version}
  };
}

1;

=encoding utf8

=head1 NAME

MCP::Server::Legacy - Fallback for clients speaking the previous protocol version

=head1 SYNOPSIS

  use MCP::Server::Legacy qw(legacy_request);

  my $bool = legacy_request('2025-11-25', {jsonrpc => '2.0', id => 1, method => 'tools/call'});

=head1 DESCRIPTION

L<MCP::Server::Legacy> answers the C<initialize> handshake of L<MCP::Constants/"LEGACY_VERSION"> clients, so they can
still list and call tools, prompts and resources while the ecosystem catches up with
L<MCP::Constants/"PROTOCOL_VERSION">. Nothing beyond that is supported, in particular no notifications and no
multi round-trip requests. It is a temporary convenience and will be removed again in a future release.

=head1 FUNCTIONS

L<MCP::Server::Legacy> implements the following functions, which can be imported individually.

=head2 legacy_context

  my $context = legacy_context($params, $context);

Populate an L<MCP::Server::Context> with the values a current request would have carried in C<_meta>.

=head2 legacy_request

  my $bool = legacy_request($version, $request);

Check if a request is made with L<MCP::Constants/"LEGACY_VERSION">, based on the C<MCP-Protocol-Version> header and
the JSON-RPC request. A request carrying C<_meta.io.modelcontextprotocol/protocolVersion> is never legacy, whatever
the header says, so a current client with a misconfigured header still gets a proper error.

=head2 legacy_result

  my $result = legacy_result($server, $method);

The result for a C<initialize> or C<ping> request, or C<undef> for every other method.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
