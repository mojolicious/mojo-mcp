package MCP::Server::Legacy;
use Mojo::Base 'Exporter', -signatures;

use MCP::Constants qw(META_PROTOCOL_VERSION);

our @EXPORT_OK = qw(legacy_context legacy_request legacy_result);

my @VERSIONS = ('2024-10-07', '2024-11-05', '2025-03-26', '2025-06-18', '2025-11-25');

sub legacy_context ($params, $context) {
  my $meta = $params->{_meta} // {};
  $context->client_capabilities({})->client_info({})->protocol_version($context->legacy);
  $context->progress_token($meta->{progressToken}) if defined $meta->{progressToken};
  return $context;
}

sub legacy_request ($version, $request) {
  my $params = $request->{params} // {};

  # The handshake exists only in legacy revisions, so answer it with the closest version we can serve
  if (($request->{method} // '') eq 'initialize') {
    my $requested = $params->{protocolVersion} // '';
    return (grep { $_ eq $requested } @VERSIONS) ? $requested : $VERSIONS[-1];
  }

  return undef if $params->{_meta}{+META_PROTOCOL_VERSION};
  return $VERSIONS[-1] unless defined $version;
  return (grep { $_ eq $version } @VERSIONS) ? $version : undef;
}

sub legacy_result ($server, $method, $version) {
  return {} if $method eq 'ping';
  return undef unless $method eq 'initialize';

  my $capabilities = {};
  $capabilities->{prompts}   = {} if @{$server->prompts};
  $capabilities->{resources} = {} if @{$server->resources};
  $capabilities->{tools}     = {} if @{$server->tools};

  return {
    protocolVersion => $version,
    capabilities    => $capabilities,
    serverInfo      => {name => $server->name, version => $server->version}
  };
}

1;

=encoding utf8

=head1 NAME

MCP::Server::Legacy - Fallback for clients speaking a previous protocol version

=head1 SYNOPSIS

  use MCP::Server::Legacy qw(legacy_request);

  my $version = legacy_request('2025-11-25', {jsonrpc => '2.0', id => 1, method => 'tools/call'});

=head1 DESCRIPTION

L<MCP::Server::Legacy> answers the C<initialize> handshake of clients speaking a protocol revision older than
L<MCP::Constants/"PROTOCOL_VERSION">, so they can still list and call tools, prompts and resources while the
ecosystem catches up. Nothing beyond that is supported, in particular no notifications and no multi round-trip
requests. It is a temporary convenience and will be removed again in a future release.

=head1 FUNCTIONS

L<MCP::Server::Legacy> implements the following functions, which can be imported individually.

=head2 legacy_context

  my $context = legacy_context($params, $context);

Populate an L<MCP::Server::Context> with the values a current request would have carried in C<_meta>.

=head2 legacy_request

  my $version = legacy_request($version, $request);

The protocol revision a request was made with, or C<undef> if it is not legacy, based on the
C<MCP-Protocol-Version> header and the JSON-RPC request. A request carrying
C<_meta.io.modelcontextprotocol/protocolVersion> is never legacy, whatever the header says, so a current client with
a misconfigured header still gets a proper error. Revisions before C<2025-06-18> predate the header, so a request
without one is assumed to be legacy.

=head2 legacy_result

  my $result = legacy_result($server, $method, $version);

The result for a C<initialize> or C<ping> request, or C<undef> for every other method. The handshake echoes the
requested protocol revision and advertises the same primitives as C<server/discover>, but never C<listChanged>,
since list change notifications are not supported.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
