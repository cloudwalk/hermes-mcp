defmodule Hermes.Server.ComponentDateTimeTest do
  use ExUnit.Case, async: true

  alias TestTools.DateListTool
  alias TestTools.DateTimeTool
  alias TestTools.DateTool
  alias TestTools.EventTool
  alias TestTools.NaiveDateTimeTool
  alias TestTools.RequiredOptionTool
  alias TestTools.TimeTool

  describe "date type transforms" do
    test "generates correct JSON Schema for date fields" do
      json_schema = DateTool.input_schema()

      assert json_schema == %{
               "type" => "object",
               "properties" => %{
                 "event_date" => %{
                   "type" => "string",
                   "format" => "date",
                   "description" => "Event date"
                 },
                 "optional_date" => %{
                   "type" => "string",
                   "format" => "date",
                   "description" => "Optional date"
                 }
               },
               "required" => ["event_date"]
             }
    end

    test "validates and transforms date strings to Date structs" do
      assert {:ok, validated} =
               DateTool.mcp_schema(%{
                 event_date: "2024-01-15",
                 optional_date: "2024-12-25"
               })

      assert validated.event_date == ~D[2024-01-15]
      assert validated.optional_date == ~D[2024-12-25]
    end

    test "accepts already parsed Date structs" do
      assert {:ok, validated} =
               DateTool.mcp_schema(%{
                 event_date: ~D[2024-01-15]
               })

      assert validated.event_date == ~D[2024-01-15]
    end

    test "rejects invalid date formats" do
      assert {:error, errors} = DateTool.mcp_schema(%{event_date: "not-a-date"})

      assert [%{message: "invalid ISO 8601 date format", path: [:event_date]}] =
               errors
    end

    test "enforces required date fields" do
      assert {:error, [error]} = DateTool.mcp_schema(%{optional_date: "2024-01-15"})
      assert %{path: [:event_date]} = error
      assert error.message =~ "is required"
    end
  end

  describe "datetime type transforms" do
    test "generates correct JSON Schema for datetime fields" do
      json_schema = DateTimeTool.input_schema()

      assert json_schema["properties"]["created_at"] == %{
               "type" => "string",
               "format" => "date-time",
               "description" => "Creation timestamp"
             }
    end

    test "validates and transforms ISO 8601 datetime strings" do
      assert {:ok, validated} =
               DateTimeTool.mcp_schema(%{
                 created_at: "2024-01-15T10:30:00Z",
                 updated_at: "2024-01-15T14:45:30.123Z"
               })

      assert %DateTime{} = validated.created_at
      assert validated.created_at.year == 2024
      assert validated.created_at.month == 1
      assert validated.created_at.day == 15
      assert validated.created_at.hour == 10
      assert validated.created_at.minute == 30
    end

    test "handles datetime with timezone offset" do
      assert {:ok, validated} =
               DateTimeTool.mcp_schema(%{
                 created_at: "2024-01-15T10:30:00-05:00"
               })

      assert %DateTime{} = validated.created_at
    end

    test "rejects invalid datetime formats" do
      assert {:error, errors} = DateTimeTool.mcp_schema(%{created_at: "2024-01-15"})

      assert [%{message: "invalid ISO 8601 datetime format", path: [:created_at]}] =
               errors
    end
  end

  describe "time type transforms" do
    test "generates correct JSON Schema for time fields" do
      json_schema = TimeTool.input_schema()

      assert json_schema["properties"]["start_time"] == %{
               "type" => "string",
               "format" => "time",
               "description" => "Start time"
             }
    end

    test "validates and transforms time strings" do
      assert {:ok, validated} = TimeTool.mcp_schema(%{start_time: "10:30:00"})
      assert validated.start_time == ~T[10:30:00]

      assert {:ok, validated} = TimeTool.mcp_schema(%{start_time: "14:45:30.123"})
      assert validated.start_time == ~T[14:45:30.123]
    end

    test "rejects invalid time formats" do
      assert {:error, errors} = TimeTool.mcp_schema(%{start_time: "25:00:00"})

      assert [%{message: "invalid ISO 8601 time format", path: [:start_time]}] =
               errors
    end
  end

  describe "naive_datetime type transforms" do
    test "validates and transforms naive datetime strings" do
      assert {:ok, validated} =
               NaiveDateTimeTool.mcp_schema(%{timestamp: "2024-01-15T10:30:00"})

      assert validated.timestamp == ~N[2024-01-15 10:30:00]
    end

    test "rejects naive datetime with timezone info" do
      assert {:error, _} =
               NaiveDateTimeTool.mcp_schema(%{timestamp: "2024-01-15T10:30:00Z"})
    end
  end

  describe "nested schemas with date/time types" do
    test "transforms dates in nested structures" do
      assert {:ok, validated} =
               EventTool.mcp_schema(%{
                 event: %{
                   name: "Conference",
                   date: "2024-06-15",
                   start_time: "09:00:00"
                 }
               })

      assert validated.event.date == ~D[2024-06-15]
      assert validated.event.start_time == ~T[09:00:00]
    end
  end

  describe "lists of date/time types" do
    test "transforms lists of dates" do
      assert {:ok, validated} =
               DateListTool.mcp_schema(%{
                 important_dates: ["2024-01-01", "2024-06-15", "2024-12-25"]
               })

      assert [~D[2024-01-01], ~D[2024-06-15], ~D[2024-12-25]] =
               validated.important_dates
    end

    test "reports errors for invalid dates in lists" do
      assert {:error, [error]} =
               DateListTool.mcp_schema(%{
                 important_dates: ["2024-01-01", "not-a-date", "2024-12-25"]
               })

      # Peri reports the error at the list level, not the individual item
      assert %{path: [:important_dates]} = error
      assert error.message =~ "invalid ISO 8601 date format"
    end
  end

  describe "field macro with required option" do
    test "required: true option generates proper schema" do
      json_schema = RequiredOptionTool.input_schema()
      assert json_schema["required"] == ["birth_date"]
    end

    test "validates required fields with new syntax" do
      assert {:ok, validated} =
               RequiredOptionTool.mcp_schema(%{
                 birth_date: "1990-01-15"
               })

      assert validated.birth_date == ~D[1990-01-15]
    end

    test "enforces required fields" do
      assert {:error, [error]} =
               RequiredOptionTool.mcp_schema(%{
                 expiry_date: "2025-01-01"
               })

      assert %{path: [:birth_date]} = error
      assert error.message =~ "is required"
    end
  end
end
