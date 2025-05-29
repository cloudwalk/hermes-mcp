# Used by "mix format"
[
  plugins: [Styler],
  import_deps: [:peri],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}", "priv/dev/upcase/{lib,config,test}/*.{ex,exs}"],
  locals_without_parens: [assert_response: 3, assert_error: 3, assert_notification: 2]
]
