package main

import (
	"context"
	"flag"
	"fmt"
	"log"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
)

func main() {
	s := server.NewMCPServer("Calculator", "0.1.0", server.WithLogging())

	tool := mcp.NewTool("calculate",
		mcp.WithDescription("Perform basic arithmetic operations"),
		mcp.WithString("operation",
			mcp.Required(),
			mcp.Description("The operation to perform (add, subtract, multiply, divide)"),
			mcp.Enum("add", "subtract", "multiply", "divide"),
		),
		mcp.WithNumber("x",
			mcp.Required(),
			mcp.Description("First number"),
		),
		mcp.WithNumber("y",
			mcp.Required(),
			mcp.Description("Second number"),
		),
	)

	s.AddTool(tool, handle_calculate_tool)

	var transport string
	flag.StringVar(&transport, "t", "stdio", "Transport type (stdio or sse)")
	flag.StringVar(
		&transport,
		"transport",
		"stdio",
		"Transport type (stdio or sse)",
	)
	flag.Parse()

	switch transport {
	case "stdio":
		if err := server.ServeStdio(s); err != nil {
			log.Fatalf("Server error: %v", err)
		}
	case "sse":
		sse := server.NewSSEServer(s, "")
		log.Printf("SSE server listening on :8000")

		if err := sse.Start(":8000"); err != nil {
			log.Fatalf("Server error: %v", err)
		}
	default:
		log.Fatalf(
			"Invalid transport type: %s. Must be 'stdio' or 'sse'",
			transport,
		)
	}
}

func handle_calculate_tool(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	op := request.Params.Arguments["operation"].(string)
	x := request.Params.Arguments["x"].(float64)
	y := request.Params.Arguments["y"].(float64)

	if op == "div" && y == 0 {
		return mcp.NewToolResultError("Cannot divide by zero"), nil
	}

	if op == "add" {
		return mcp.NewToolResultText(fmt.Sprintf("%v", x+y)), nil
	}

	if op == "mult" {
		return mcp.NewToolResultText(fmt.Sprintf("%v", x*y)), nil
	}

	if op == "sub" {
		return mcp.NewToolResultText(fmt.Sprintf("%v", x-y)), nil
	}

	if op == "div" {
		return mcp.NewToolResultText(fmt.Sprintf("%v", x/y)), nil
	}

	return mcp.NewToolResultError(fmt.Sprintf("operation %s isn't supported", op)), nil
}
