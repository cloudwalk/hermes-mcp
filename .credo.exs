%{
  configs: [
    %{
      name: "default",
      strict: true,
      checks: %{
        disabled: [
          {Credo.Check.Design.TagTODO, []},
        ]
      }
    }
  ]
}
