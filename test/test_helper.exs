Application.ensure_all_started(:mimic)

Mox.defmock(Hermes.MockTransport, for: Hermes.Transport.Behaviour)

if Code.ensure_loaded?(:gun), do: Mimic.copy(:gun)

ExUnit.start()
