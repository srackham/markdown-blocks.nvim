--- Module initialisation
local M = {}

local utils = require("markdown-blocks.utils")

--- @class WrapOptions
--- @field column_number? number The wrap column number (defaults to 0).
--- @field unwrap? boolean Unwrap instead of wrapping (defaults to false).

--- Wraps/unwraps each paragraph in the lines array and returns the updated lines.
--- @param lines string[] The lines to wrap/unwrap.
--- @param opts? WrapOptions
--- @return string[] The wrapped/unwrapped lines.
local function wrap_paragraphs(lines, opts)
  opts = opts or {}
  local column_number = opts.column_number or 0
  local unwrap = opts.unwrap or false
  local result = {}
  local paragraph = {}

  -- Wrap `paragraph` and append to `result`
  local function wrap_paragraph()
    if #paragraph == 0 then
      return
    end

    -- Join all lines into a single string
    local joined_text = table.concat(paragraph, ' ')
    local wrapped_lines
    if unwrap then
      wrapped_lines = { joined_text }
    else
      -- Split the text at the wrap column into an array of wrapped lines
      local indent = joined_text:match('^(%s*)')
      wrapped_lines = utils.wrap_str(joined_text, column_number - #indent)

      -- Indent all lines with the same indent as the first line
      utils.indent_lines(wrapped_lines, indent)
    end

    -- Append wrapped paragraph to result
    for _, line in ipairs(wrapped_lines) do
      table.insert(result, line)
    end

    paragraph = {}
  end

  for _, line in ipairs(lines) do
    if line == '' then -- Paragraph break
      wrap_paragraph()
      table.insert(result, line)
    else
      table.insert(paragraph, line)
    end
  end
  wrap_paragraph()
  return result
end

--- Wraps the current block (visual selection or paragraph).
--- Uses the specified `column_number` or the current cursor column if
--- `column_number` is nil. Preserves indentation of the first line of
--- each paragraph within the block.
--- @param column_number number|nil The 1-based column number to wrap at. Defaults to the current cursor column.
function M.wrap_block(column_number)
  -- Get the cursor column for wrapping
  local col = column_number or vim.fn.col('.')
  utils.map_block(function(lines)
    local wrapped_lines = wrap_paragraphs(lines, { column_number = col })
    return wrapped_lines
  end)
end

--- Unwraps the current block (visual selection or paragraph).
--- Joins lines within each paragraph of the block into single lines,
--- separated by spaces.
function M.unwrap_block()
  utils.map_block(function(lines)
    local joined_lines = wrap_paragraphs(lines, { unwrap = true })
    return joined_lines
  end)
end

--- Toggles quoting (prefix '> ') for the current block (visual selection or paragraph).
--- If the first line of the block starts with '> ' then
--- it removes the '> ' prefix from all lines that have it.
--- Otherwise, it prepends '> ' to every line in the block.
function M.quote_block()
  utils.map_block(function(lines)
    if lines[1]:match('^>') then
      -- If the first line starts with '>', remove it from this and from any subsequent lines
      for i, line in ipairs(lines) do
        lines[i] = line:gsub('^>%s?', '')
      end
    else
      -- If the first line does not start with '>', prepend '> ' to every line
      for i, line in ipairs(lines) do
        lines[i] = '> ' .. line
      end
    end
    return lines
  end)
end

--- Toggles trailing backslash line continuation markers (` \`) on lines in a table.
--- If the first line ends with ` \` (ignoring trailing whitespace), it removes
--- the ` \` from all lines ending with it.
--- Otherwise, it appends ` \` to lines, skipping blank lines, lines already
--- ending in `\`, and lines immediately preceding a blank line.
--- Modifies the input table `lines` in place.
--- @param lines table An array of strings representing lines of text.
function M.toggle_line_breaks(lines)
  -- Check if the first line ends with '\' preceded by zero or more whitespace characters
  if lines[1]:match('%s*\\$') then
    -- If the first line ends with '\', remove it and the whitespace on this and all subsequent lines
    for i, line in ipairs(lines) do
      if line:match('%s*\\$') then
        lines[i] = line:gsub('%s*\\$', '') -- Remove '\' and preceding whitespace
      end
    end
  else
    -- The first line does not end with '\' so append ' \' line breaks skipping blank lines and lines preceeding blank lines
    for i, line in ipairs(lines) do
      -- Don't break blank lines or lines followed by a blank line or lines that are already broken
      local skip = line == '' or (i < #lines and lines[i + 1] == '') or line:match('\\$')
      if not skip then
        lines[i] = line .. ' \\'
      end
    end
  end
end

--- Toggles line continuation markers (` \`) for the current block (visual selection or paragraph).
--- Adds or removes trailing ` \` based on the state of the first line.
--- Does not add a marker to blank lines, lines already ending in `\`, or the
--- line immediately preceding a blank line. Ensures the very last line of
--- a paragraph block does not end with ` \`.
function M.break_block()
  utils.map_block(function(lines, opts)
    M.toggle_line_breaks(lines)
    -- Ensure the last line of a paragraph does not get a break
    if opts.end_of_paragraph then
      lines[#lines] = lines[#lines]:gsub('%s*\\$', '') -- Remove '\' and any preceding whitespace from the last element
    end
    return lines
  end)
end

--- Numbers or renumbers non-indented list items in a table of lines.
--- Affects lines starting with non-whitespace.
--- If a line already starts with `digits.` + whitespace, it's renumbered sequentially.
--- If a line starts with non-whitespace but not a number pattern, `N. ` is prepended.
--- Indented lines are skipped. Renumbering is sequential across affected lines.
--- Modifies the input table `lines` in place.
--- @param lines table An array of strings representing lines of text.
local function number_lines(lines)
  local item_number = 1
  for i, line in ipairs(lines) do
    if line:match('^%d+%.%s') then -- Renumber the current line
      lines[i] = line:gsub('^%d+%.%s+(.*)$', item_number .. '. ' .. '%1')
      item_number = item_number + 1
    elseif line:match('^%S') then -- Prepend a line number to the current line
      lines[i] = item_number .. '. ' .. line
      item_number = item_number + 1
    end
  end
end

--- Removes list numbering (`N. `) from the start of lines in a table.
--- Affects lines starting with the pattern `digits.` + whitespace.
--- Modifies the input table `lines` in place.
--- @param lines table An array of strings representing lines of text.
local function unnumber_lines(lines)
  for i, line in ipairs(lines) do
    if line:match('^%d+%.%s') then
      lines[i] = line:gsub('^%d+%.%s+(.*)$', '%1')
    end
  end
end

--- Sequentially renumbers existing ordered list items (`N. `) in a table of lines.
--- Resets numbering for each indentation level independently. Handles nested lists.
--- Only affects lines that already match the `indent digits.` + whitespace pattern.
--- Formats the number part like `N.   ` (padded/aligned).
--- Modifies the input table `lines` in place.
--- @param lines table An array of strings representing lines of text.
local function renumber_lines(lines)
  local list_numbers = {}
  for i, line in ipairs(lines) do
    local indent, text = line:match('^(%s*)(.*)$')
    if text == '' then -- Skip blank lines
      goto continue
    end
    -- indent = indent:gsub('\t', '    ') -- Expand indent tabs to 4 spaces
    -- Discontinue lists whose indent is encroached into by the current line
    for list_indent, _ in pairs(list_numbers) do
      if #indent < #list_indent then
        list_numbers[list_indent] = 1
      end
    end
    if text:match('^%d+%.%s') then
      if list_numbers[indent] == nil then -- First occurence of a list at this indent
        list_numbers[indent] = 1
      end
      lines[i] = text:gsub('^%d+%.%s+(.*)$', indent .. string.format('%-4s', list_numbers[indent] .. '.') .. '%1')
      list_numbers[indent] = list_numbers[indent] + 1
    end
    ::continue::
  end
end

-- Number/unnumber non-indented lines in the current block.
-- If the first line is numbered delete list item numbers from non-indented lines.
-- If the first line is not numbered add/update list item numbers from non-indented lines.
function M.number_block()
  utils.map_block(function(lines)
    if lines[1]:match('^%s*%d+%.%s') then
      unnumber_lines(lines)
    else
      number_lines(lines)
    end
    return lines
  end)
end

--- Sequentially renumbers existing ordered list items (`N. `) in the current block.
--- Affects the visual selection or the paragraph under the cursor.
--- Respects indentation levels to handle nested lists correctly, using `renumber_lines`.
function M.renumber_block()
  utils.map_block(function(lines)
    renumber_lines(lines)
    return lines
  end)
end

--- Enclose block with Markdown ruler (`---`) lines.
--- Rulers are preceeded by a blank line so they are not mistaken for Setext header underilines.
function M.ruled_block()
  utils.map_block(function(lines)
    table.insert(lines, 1, "")
    table.insert(lines, 2, "---")
    table.insert(lines, "")
    table.insert(lines, "---")
    return lines
  end)
  utils.move_cursor(-1, 0) -- Move cursor up 1 line so the ruler is fully rendered by render-markdown.nvim
end

--- Convert CSV paragraph/selection to a Markdown table.
function M.csv_to_markdown_table()
  utils.map_block(function(lines)
    local csv_str = table.concat(lines, '\n')
    local md_str = utils.csv_to_markdown(csv_str)
    local md_lines = {}
    for line in md_str:gmatch('[^\n]+') do
      table.insert(md_lines, line)
    end
    return md_lines
  end)
  -- Move cursor past the end of the table so it is fully rendered by render-markdown.nvim
  -- Ignore past end of file error.
  pcall(function() utils.move_cursor(2, 0) end)
end

return M
