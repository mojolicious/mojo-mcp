package MCP;
use Mojo::Base -base, -signatures;

our $VERSION = '0.08';

1;

=encoding utf8

=head1 NAME

MCP - Model Context Protocol Perl SDK

=head1 SYNOPSIS

  use Mojolicious::Lite -signatures;

  use MCP::Server;

  my $server = MCP::Server->new;
  $server->tool(
    name         => 'time',
    description  => 'Get the current local time',
    code         => sub ($tool, $args) {
      return localtime(time);
    }
  );

  any '/mcp' => $server->to_action;

  app->start;

=head1 DESCRIPTION

Connect Perl with AI using the Model Context Protocol (MCP). Currently this module is focused on tool calling and
prompts, but it will be extended to support other MCP features in the future. At its core, MCP is all about text
processing, making it a great fit for Perl.

=head3 Streamable HTTP Transport

Use the L<MCP::Server/"to_action"> method to add an MCP endpoint to any L<Mojolicious> application. The tool name and
description are used for discovery, and the L<JSON schema|https://json-schema.org> is used to validate the input.

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

Authentication can be added by the web application, just like for any other route. To allow for MCP applications to
scale with prefork web servers, server to client streaming is currentlly avoided when possible.

=head3 Stdio Transport

Build local command line applications and use the stdio transport for testing with the L<MCP::Server/"to_stdio">
method.

  use Mojo::Base -strict, -signatures;

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

  $server->to_stdio;

Just run the script and type requests on the command line.

  $ perl examples/echo_stdio.pl
  {"jsonrpc":"2.0","id":"1","method":"tools/list"}
  {"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"echo","arguments":{"msg":"hello perl"}}}

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2025-2026, Sebastian Riedel.

This program is free software, you can redistribute it and/or modify it under the terms of the MIT license.

=head1 SEE ALSO

L<Mojolicious>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
