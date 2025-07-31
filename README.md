
# MCP Perl SDK

 [![](https://github.com/mojolicious/mojo-mcp/workflows/linux/badge.svg)](https://github.com/mojolicious/mojo-mcp/actions) [![](https://github.com/mojolicious/mojo-mcp/workflows/macos/badge.svg)](https://github.com/mojolicious/mojo-mcp/actions)

  [Model Context Protocol](https://modelcontextprotocol.io/) support for [Perl](https://perl.org) and the
  [Mojolicious](https://mojolicious.org) real-time web framework.

### Features

Please be aware that this module is still in development and will be changing rapidly. Additionally the MCP
specification is getting regular updates which we will implement. Breaking changes are very likely.

  * Tool calling
  * Async tools with support for promises
  * Streamable HTTP and Stdio transports
  * HTTP client for testing
  * Can be embedded in Mojolicious web apps

## Streamable HTTP Transport

Use the `to_action` method to add an MCP endpoint to any Mojolicious application.

```perl
use Mojolicious::Lite -signatures;

use MCP::Server;

my $server = MCP::Server->new;
$server->tool(
  name         => 'echo',
  description  => 'Echo the input text',
  input_schema => {type => 'object', properties => {test => {type => 'string'}}, required => ['test']},
  code         => sub ($tool, $args) {
    return "Echo: $args->{test}";
  }
);

any '/mcp' => $server->to_action;

app->start;
```

Authentication can be added by the web application, just like for any other route.

## Stdio Transport

Build local command line applications and use the stdio transport for testing with the `to_stdio` method.

```perl
use Mojo::Base -strict, -signatures;

use MCP::Server;

my $server = MCP::Server->new;
$server->tool(
  name         => 'echo',
  description  => 'Echo the input text',
  input_schema => {type => 'object', properties => {test => {type => 'string'}}, required => ['test']},
  code         => sub ($tool, $args) {
    return "Echo: $args->{test}";
  }
);

$server->to_stdio;
```

Just run the script and type requests on the command line.

```
$ perl examples/echo_stdio.pl
{"jsonrpc":"2.0","id":"1","method":"tools/list"}
{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"echo","arguments":{"test":"hello perl"}}}
```
