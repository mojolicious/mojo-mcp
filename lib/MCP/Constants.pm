package MCP::Constants;
use Mojo::Base 'Exporter';

use constant {
  INVALID_PARAMS   => -32602,
  INVALID_REQUEST  => -32600,
  METHOD_NOT_FOUND => -32601,
  PARSE_ERROR      => -32700,
  PROTOCOL_VERSION => '2025-06-18'
};

our @EXPORT_OK = qw(INVALID_PARAMS INVALID_REQUEST METHOD_NOT_FOUND PARSE_ERROR PROTOCOL_VERSION);

1;

=encoding utf8

=head1 NAME

MCP::Constants - Constants for the Model Context Protocol (MCP)

=head1 SYNOPSIS

  use MCP::Constants qw(PROTOCOL_VERSION);

=head1 DESCRIPTION

L<MCP::Constants> provides constants used in the Model Context Protocol (MCP).

=head1 CONSTANTS

L<MCP::Constants> exports the following constants.

=head2 INVALID_PARAMS

The error code for invalid parameters.

=head2 INVALID_REQUEST

The error code for an invalid request.

=head2 METHOD_NOT_FOUND

The error code for a method that was not found.

=head2 PARSE_ERROR

The error code for a parse error.

=head2 PROTOCOL_VERSION

The version of the Model Context Protocol being used.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
