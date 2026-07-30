package MCP::Constants;
use Mojo::Base 'Exporter';

use constant {
  HEADER_MISMATCH              => -32020,
  INSUFFICIENT_SCOPE           => -32003,
  INTERNAL_ERROR               => -32603,
  INVALID_PARAMS               => -32602,
  INVALID_REQUEST              => -32600,
  META_CLIENT_CAPABILITIES     => 'io.modelcontextprotocol/clientCapabilities',
  META_CLIENT_INFO             => 'io.modelcontextprotocol/clientInfo',
  META_LOG_LEVEL               => 'io.modelcontextprotocol/logLevel',
  META_PROTOCOL_VERSION        => 'io.modelcontextprotocol/protocolVersion',
  META_SERVER_INFO             => 'io.modelcontextprotocol/serverInfo',
  META_SUBSCRIPTION_ID         => 'io.modelcontextprotocol/subscriptionId',
  METHOD_NOT_FOUND             => -32601,
  MISSING_CLIENT_CAPABILITY    => -32021,
  PARSE_ERROR                  => -32700,
  PROTOCOL_VERSION             => $ENV{MOJO_MCP_VERSION} || '2026-07-28',
  UNSUPPORTED_PROTOCOL_VERSION => -32022
};

use constant SUPPORTED_VERSIONS => [PROTOCOL_VERSION];

our @EXPORT_OK = (
  qw(HEADER_MISMATCH INSUFFICIENT_SCOPE INTERNAL_ERROR INVALID_PARAMS INVALID_REQUEST META_CLIENT_CAPABILITIES),
  qw(META_CLIENT_INFO META_LOG_LEVEL META_PROTOCOL_VERSION META_SERVER_INFO META_SUBSCRIPTION_ID),
  qw(METHOD_NOT_FOUND MISSING_CLIENT_CAPABILITY PARSE_ERROR PROTOCOL_VERSION SUPPORTED_VERSIONS),
  qw(UNSUPPORTED_PROTOCOL_VERSION)
);

1;

=encoding utf8

=head1 NAME

MCP::Constants - Constants for MCP (Model Context Protocol)

=head1 SYNOPSIS

  use MCP::Constants qw(PROTOCOL_VERSION);

=head1 DESCRIPTION

L<MCP::Constants> provides constants used in MCP (Model Context Protocol).

=head1 CONSTANTS

L<MCP::Constants> exports the following constants.

=head2 HEADER_MISMATCH

The error code for a request whose routing headers disagree with its JSON-RPC body.

=head2 INSUFFICIENT_SCOPE

The error code for a request whose access token lacks a required OAuth scope. This is a local authorization policy
rather than a spec-defined code, and lives in the C<-32000> to C<-32019> range the specification grandfathers for
existing SDK use; C<-32020> to C<-32099> is reserved for the specification itself.

=head2 INTERNAL_ERROR

The error code for a prompt, resource, or tool that died, or returned a promise that was rejected.

=head2 INVALID_PARAMS

The error code for invalid parameters. Also used for prompts, resources, and tools that were not found.

=head2 INVALID_REQUEST

The error code for an invalid request.

=head2 META_CLIENT_CAPABILITIES

The C<_meta> key carrying the capabilities of the client making the request.

=head2 META_CLIENT_INFO

The C<_meta> key carrying the name and version of the client making the request.

=head2 META_LOG_LEVEL

The C<_meta> key carrying the minimum log level the client wants to receive for a request.

=head2 META_PROTOCOL_VERSION

The C<_meta> key carrying the protocol version a request is made with.

=head2 META_SERVER_INFO

The C<_meta> key carrying the name and version of the server in a result.

=head2 META_SUBSCRIPTION_ID

The C<_meta> key carrying the subscription a notification belongs to.

=head2 METHOD_NOT_FOUND

The error code for a method that was not found.

=head2 MISSING_CLIENT_CAPABILITY

The error code for a request that requires a client capability the client did not declare.

=head2 PARSE_ERROR

The error code for a parse error.

=head2 PROTOCOL_VERSION

The version of the Model Context Protocol being used.

=head2 SUPPORTED_VERSIONS

An array reference with every protocol version the server accepts, newest first.

=head2 UNSUPPORTED_PROTOCOL_VERSION

The error code for a request made with a protocol version the server does not support.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
