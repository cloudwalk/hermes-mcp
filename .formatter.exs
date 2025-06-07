# Used by "mix format"
locals = [
  assert_response: 3,
  assert_error: 3,
  assert_notification: 2,
  component: 1,
  component: 2,
  schema: 1
]

[
  plugins: [Styler],
  import_deps: [:peri],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}", "priv/dev/upcase/{lib,config,test}/*.{ex,exs}"],
  locals_without_parens: locals,
  export: locals
]
