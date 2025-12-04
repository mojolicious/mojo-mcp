
# MCP Perl SDK

 [![](https://github.com/mojolicious/mojo-mcp/workflows/linux/badge.svg)](https://github.com/mojolicious/mojo-mcp/actions) [![](https://github.com/mojolicious/mojo-mcp/workflows/macos/badge.svg)](https://github.com/mojolicious/mojo-mcp/actions)

  [Model Context Protocol](https://modelcontextprotocol.io/) support for [Perl](https://perl.org) and the
  [Mojolicious](https://mojolicious.org) real-time web framework.

### Features

Please be aware that this module is still in development and will be changing rapidly. Additionally the MCP
specification is getting regular updates which we will implement. Breaking changes are very likely.

  * Tool calling, prompts and resources
  * Streamable HTTP and Stdio transports
  * Scalable with pre-forking web server and async tools using promises
  * HTTP client for testing
  * Can be embedded in Mojolicious web apps

## Installation

  All you need is Perl 5.20 or newer. Just install from [CPAN](https://metacpan.org/pod/MCP).

    $ cpanm -n MCP

  We recommend the use of a [Perlbrew](http://perlbrew.pl) environment.

## Streamable HTTP Transport

Use the `to_action` method to add an MCP endpoint to any Mojolicious application.

```perl
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
  input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
  code         => sub ($tool, $args) {
    return "Echo: $args->{msg}";
  }
);

$server->to_stdio;
```

Just run the script and type requests on the command line.

```
$ perl examples/echo_stdio.pl
{"jsonrpc":"2.0","id":"1","method":"tools/list"}
{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"echo","arguments":{"msg":"hello perl"}}}
```
