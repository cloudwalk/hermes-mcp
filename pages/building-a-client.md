# Building a Client

Let's explore how to connect your Elixir application to MCP servers. What possibilities open up when your code can leverage AI-enhanced services?

## Starting Simple

Remember our first client? Let's understand what's happening:

```elixir
defmodule MyApp.WeatherClient do
  use Hermes.Client,
    name: "MyApp",                    # How you introduce yourself
    version: "1.0.0",                 # Your client's version
    protocol_version: "2024-11-05",   # MCP protocol target version
    capabilities: [:roots]            # What features you support
end
```

When you add this to your supervision tree, something interesting happens:

```elixir
{MyApp.WeatherClient,
 transport: {:stdio, command: "weather-server", args: []}}
```

The client automatically:

- Launches the weather server as a subprocess
- Negotiates capabilities
- Maintains the connection
- Handles all the protocol details

How might you use this connection?

## Discovering Capabilities

What can a connected server actually do? Let's find out:

```elixir
# What's this server about?
info = MyApp.WeatherClient.get_server_info()
# => %{"name" => "Weather Server", "version" => "2.0.0", ...}

# What capabilities does it offer?
caps = MyApp.WeatherClient.get_server_capabilities()
# => %{"tools" => %{"listChanged" => false}, ...}

# What tools are available?
{:ok, %{result: %{"tools" => tools}}} = MyApp.WeatherClient.list_tools()

Enum.each(tools, fn tool ->
  IO.puts("#{tool["name"]}: #{tool["description"]}")
end)
# => get_weather: Get current weather for a location
# => get_forecast: Get weather forecast
```

Notice how we're exploring the server's interface dynamically?

## Using Tools

Now for the interesting part - actually using these discovered tools:

```elixir
# Simple tool call
{:ok, %{result: weather}} =
  MyApp.WeatherClient.call_tool("get_weather", %{
    "location" => "San Francisco"
  })

# Tool with complex parameters
{:ok, %{result: forecast}} =
  MyApp.WeatherClient.call_tool("get_forecast", %{
    "location" => "Tokyo",
    "days" => 5,
    "units" => "metric"
  })
```

What happens if something goes wrong?

```elixir
case MyApp.WeatherClient.call_tool("get_weather", %{"location" => ""}) do
  {:ok, %{is_error: false, result: weather}} ->
    # Success path

  {:ok, %{is_error: true, result: error}} ->
    # The tool itself reported an error
    IO.puts("Tool error: #{error["message"]}")

  {:error, error} ->
    # Protocol or connection error
    IO.puts("Connection error: #{inspect(error)}")
end
```

## Working with Resources

Some servers expose resources - think files, databases, or any readable content:

```elixir
# What resources are available?
{:ok, %{result: %{"resources" => resources}}} =
  MyApp.WeatherClient.list_resources()

# Read a specific resource
{:ok, %{result: %{"contents" => contents}}} =
  MyApp.WeatherClient.read_resource("weather://stations/KSFO")

# Resources can have multiple content types
for content <- contents do
  case content do
    %{"text" => text} ->
      IO.puts("Text content: #{text}")

    %{"blob" => blob} ->
      IO.puts("Binary data: #{byte_size(blob)} bytes")
  end
end
```

## Transport Options

How does your client actually connect to servers? Let's explore the options:

```elixir
# Local subprocess
transport: {:stdio, command: "python", args: ["-m", "my_server"]}

# HTTP endpoint
transport: {:streamable_http, base_url: "http://localhost:8000"}

# WebSocket for real-time
transport: {:websocket, base_url: "ws://localhost:8000"}

# Server-Sent Events
transport: {:sse, base_url: "http://localhost:8000"}
```

Which transport should you choose?

- **STDIO**: Perfect for local tools and subprocess isolation
- **HTTP**: Great for remote services and web APIs
- **WebSocket**: When you need bidirectional real-time communication
- **SSE**: For servers that push updates to clients (deprecated)

## Advanced Patterns

### Multiple Client Instances

Need to connect to multiple servers? No problem:

```elixir
children = [
  Supervisor.child_spec(
    {MyApp.WeatherClient,
     name: :weather_us,
     transport: {:stdio, command: "weather-server", args: ["--region", "US"]}},
    id: :weather_us
  ),

  Supervisor.child_spec(
    {MyApp.WeatherClient,
     name: :weather_eu,
     transport: {:stdio, command: "weather-server", args: ["--region", "EU"]}},
    id: :weather_eu
  )
]

# Use specific instances
MyApp.WeatherClient.call_tool(:weather_us, "get_weather", %{location: "NYC"})
MyApp.WeatherClient.call_tool(:weather_eu, "get_weather", %{location: "Paris"})
```

### Handling Timeouts

Long-running operations? Adjust timeouts:

```elixir
# 5 minute timeout for slow operations
opts = [timeout: 300_000]
MyApp.WeatherClient.call_tool("analyze_historical_data", params, opts)
```

### Progress Tracking

Need to track progress on long-running operations? Here's how:

```elixir
# Generate a unique token for this operation
progress_token = Hermes.MCP.ID.generate_progress_token()

# Option 1: Just track with a token
MyApp.WeatherClient.call_tool("analyze_data", params,
  progress: [token: progress_token]
)

# Option 2: Receive real-time updates
callback = fn ^progress_token, progress, total ->
  percentage = if total, do: "#{progress}/#{total}", else: "#{progress}"
  IO.puts("Progress: #{percentage}")
end

MyApp.WeatherClient.call_tool("analyze_data", params,
  progress: [token: progress_token, callback: callback]
)
```

The server sends progress notifications that your callback receives automatically.

## Graceful Shutdown

When you're done:

```elixir
MyApp.WeatherClient.close()
```

This cleanly shuts down the connection and any associated resources.

## What's Next?

Now that you understand clients, what interests you?

- Building your own server to expose functionality?
- Exploring specific recipes for common patterns?
- Understanding how to handle errors gracefully?

The client abstraction handles all the protocol complexity - you just focus on using the capabilities. What will you connect to first?
