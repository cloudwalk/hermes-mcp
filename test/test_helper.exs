Application.ensure_all_started(:mimic)

if Code.ensure_loaded?(:gun), do: Mimic.copy(:gun)

ExUnit.start()
