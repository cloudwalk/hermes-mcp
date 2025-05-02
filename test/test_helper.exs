Mox.defmock(Hermes.MockTransport, for: Hermes.Transport.Behaviour)

Application.ensure_all_started(:mimic)
Mimic.copy(Hermes.MockTransport)
Mimic.copy(:gun)

ExUnit.start()
