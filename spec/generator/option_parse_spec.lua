-- L1 unit test for liv.generator option-doc parsing (pure Lua, no editor).
-- Parses Vim/Neovim `runtime/doc/options.txt` blocks into {name, type, scope}.
local parse = require("liv.generator.option.parse")

describe("liv.generator.option.parse", function()
  it("parses a boolean option local to buffer", function()
    local got = parse([['expandtab' 'et'	boolean	(default off)
			local to buffer
	In Insert mode: Use the appropriate number of spaces.]])
    assert.same({ { name = "expandtab", type = "boolean", scope = "buffer" } }, got)
  end)

  it("parses a number option that is global", function()
    local got = parse([['aleph' 'al'	number	(default 224)
			global
	The ASCII code for the first letter of the Hebrew alphabet.]])
    assert.same({ { name = "aleph", type = "number", scope = "global" } }, got)
  end)

  it("parses a string option local to window", function()
    local got = parse([['foldtext' 'fdt'	string	(default "foldtext()")
			local to window
	An expression which is used to specify the text displayed for a fold.]])
    assert.same({ { name = "foldtext", type = "string", scope = "window" } }, got)
  end)

  it("defaults to global scope when no scope line is present", function()
    local got = parse([['option_no_scope'	boolean	(default off)
	Some option without an explicit scope line.]])
    assert.same({ { name = "option_no_scope", type = "boolean", scope = "global" } }, got)
  end)

  it("parses an option with no short name", function()
    local got = parse([['autoread'	boolean	(default off)
			global or local to buffer |global-local|]])
    assert.same({ { name = "autoread", type = "boolean", scope = "buffer" } }, got)
  end)

  it("parses multiple options and ignores prose", function()
    local got = parse([[Some introductory prose that mentions 'quotes' but is not a block.

'wrap' 'nowrap'	boolean	(default on)
			local to window
	This option changes how text is displayed.

'textwidth' 'tw'	number	(default 0)
			local to buffer
	Maximum width of text that is being inserted.]])
    assert.same({
      { name = "wrap", type = "boolean", scope = "window" },
      { name = "textwidth", type = "number", scope = "buffer" },
    }, got)
  end)
end)
