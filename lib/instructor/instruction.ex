defmodule Instructor.Instruction do
  use Flint.Extension

  option :doc, default: "", validator: &is_binary/1, required: false
end
