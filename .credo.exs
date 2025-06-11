%{
  configs: [
    %{
      name: "default",
      strict: true,
      checks: %{
        disabled: [
          {Credo.Check.Design.TagTODO, []},
          {Credo.Check.Refactor.LongQuoteBlocks, ignore_comments: true}
        ]
      }
    }
  ]
}
