Mox.defmock(Hermes.MockTransport, for: Hermes.Transport.Behaviour)

Application.ensure_all_started(:mimic)
Mimic.copy(Hermes.MockTransport)

if Code.ensure_loaded?(:gun), do: Mimic.copy(:gun)

ExUnit.start()
