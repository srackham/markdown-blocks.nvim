--- Module initialisation
local M = {}

local utils = require("markdown-blocks.utils")

-- Helper to normalize indent: tabs as 4 spaces, other whitespace as 1 space
local function normalize_indent(ws)
  local indent = ""
  for c in ws:gmatch(".") do
    if c == "\t" then
      indent = indent .. "    "
    elseif c:match("%s") then
      indent = indent .. " "
    end
  end
  return indent
end

-- Helper to join lines with single space, dropping all but first indent
local function join_with_single_space(lines, keep_first_indent)
  if #lines == 0 then return "" end
  local first_indent = lines[1]:match("^(%s*)") or ""
  local norm_indent = normalize_indent(first_indent)
  local texts = {}
  for _, line in ipairs(lines) do
    local text = line:gsub("^%s*", "")
    table.insert(texts, text)
  end
  local joined = table.concat(texts, " ")
  if keep_first_indent then
    return norm_indent .. joined
  else
    return joined
  end
end

--- @class WrapOptions
--- @field column_number? number The wrap column number (defaults to 0).
--- @field unwrap? boolean Unwrap instead of wrapping (defaults to false).
--- @field retain_indent? boolean If true, retains the first line's indent for all wrapped lines, adjusting column width accordingly.

--- Wraps or unwraps each paragraph in the lines array and returns the updated lines.
--- If `retain_indent` is true, when wrapping, the indent of the first line (leading whitespace with tabs as 4 spaces, others as 1 space)
--- is used for all wrapped lines, and its width is subtracted from `column_number` to keep right margins consistent.
--- When unwrapping, only the first line's indent is retained in the result; other lines' indents are dropped and joined with a space.
--- @param lines string[] The lines to wrap or unwrap.
--- @param opts? WrapOptions
--- @return string[] The wrapped or unwrapped lines.
local function wrap_paragraphs(lines, opts)
  opts = opts or {}
  local column_number = opts.column_number or 0
  local unwrap = opts.unwrap or false
  local retain_indent = opts.retain_indent or false
  local result = {}
  local paragraph = {}

  -- Wrap `paragraph` and append to `result`
  local function wrap_paragraph()
    if #paragraph == 0 then
      return
    end

    if unwrap then
      local unwrapped = join_with_single_space(paragraph, true)
      table.insert(result, unwrapped)
    else
      -- Get and normalize indent from first line
      local first_indent = paragraph[1]:match("^(%s*)") or ""
      local norm_indent = retain_indent and normalize_indent(first_indent) or (first_indent or "")
      -- Join lines to single string, removing leading whitespace
      local joined_text = join_with_single_space(paragraph, false)
      -- Adjust wrap column for indent width
      local wrap_col = column_number
      if retain_indent then
        wrap_col = math.max(0, column_number - #norm_indent)
      end
      -- Wrap the text
      local wrapped_lines = utils.wrap_str(joined_text, wrap_col)
      -- Indent all lines with the normalized indent if retain_indent is true
      if retain_indent then
        for i, line in ipairs(wrapped_lines) do
          wrapped_lines[i] = norm_indent .. line
        end
      else
        -- Use original indent for first line only
        if #wrapped_lines > 0 then
          wrapped_lines[1] = (first_indent or "") .. wrapped_lines[1]
        end
      end
      -- Append to result
      for _, line in ipairs(wrapped_lines) do
        table.insert(result, line)
      end
    end

    paragraph = {}
  end

  for _, line in ipairs(lines) do
    if line == "" then -- Paragraph break
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
    local wrapped_lines = wrap_paragraphs(lines, { column_number = col, retain_indent = true })
    return wrapped_lines
  end)
end

--- Unwraps the current block (visual selection or paragraph).
--- Joins lines within each paragraph of the block into single lines,
--- separated by spaces.
function M.unwrap_block()
  utils.map_block(function(lines)
    local joined_lines = wrap_paragraphs(lines, { unwrap = true, retain_indent = true })
    return joined_lines
  end)
end

--- Toggles a prefix on each line in a block of text.
-- If the first line matches the given pattern, removes the pattern from all lines.
-- Otherwise, prepends the given prefix to all lines, optionally skipping blank lines.
-- @param pattern string: Lua pattern to match at the start of each line.
-- @param prefix string: Prefix to prepend to each line if the pattern is not matched.
-- @param opts table|nil: Optional table of options.
--   - skip_blank_lines (boolean): If true, blank lines will not have the prefix added. Default is false.
local function toggle_line_prefix(pattern, prefix, opts)
  opts = opts or {}
  utils.map_block(function(lines)
    if lines[1]:match(pattern) then
      for i, line in ipairs(lines) do
        lines[i] = line:gsub(pattern, '')
      end
    else
      for i, line in ipairs(lines) do
        if line == "" and opts.skip_blank_lines then
          -- Skip blank lines
        else
          lines[i] = prefix .. line
        end
      end
    end
    return lines
  end)
end

--- Toggles quoting (prefix '> ') for the current block (visual selection or paragraph).
--- If the first line of the block starts with '> ' then
--- it removes the '> ' prefix from all lines that have it.
--- Otherwise, it prepends '> ' to every line in the block.
function M.quote_block()
  toggle_line_prefix('^>%s?', '> ')
end

--- Converts the current block into a markdown-style list.
-- Prepends "- " to each non-blank line, or removes it if already present.
function M.list_block()
  toggle_line_prefix('^-%s+', '- ', { skip_blank_lines = true })
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

--- Toggle block with start and end delimiter lines.
function M.delimit_block(start_delimiter, end_delimiter)
  utils.map_block(function(lines)
    if lines[1] == start_delimiter then
      -- Remove start delimiter
      table.remove(lines, 1)
      -- Only remove end delimiter if we removed the start
      if lines[#lines] == end_delimiter then
        table.remove(lines, #lines)
      end
    else
      -- Insert delimiters
      table.insert(lines, 1, start_delimiter)
      table.insert(lines, end_delimiter)
    end
    return lines
  end)
end

--- Enclose block with Markdown ruler (`___`) lines.
function M.ruled_block()
  M.delimit_block('___', '___')
end

--- Enclose block with code block fences and a language code.
function M.code_block(lang)
  lang = lang or ''
  M.delimit_block('```' .. lang, '```')
end

--- Enclose block with HTML blockquote
function M.blockquote_block(lang)
  lang = lang or ''
  M.delimit_block('<blockquote>' .. lang, '</blockquote>')
end

--- Convert CSV paragraph/selection to a Markdown table.
function M.csv_to_markdown_table()
  utils.map_block(function(lines)
    local csv_str = table.concat(lines, '\n')
    local md_str = utils.csv_to_markdown(csv_str)
    vim.fn.setreg('+', md_str)
    vim.fn.setreg('"', md_str)
    local md_lines = {}
    for line in md_str:gmatch('[^\n]+') do
      table.insert(md_lines, line)
    end
    return md_lines
  end)
  -- Move cursor past the end of the table so it is fully rendered by render-markdown.nvim
  utils.move_cursor(2, 0)
end

--- Convert CSV paragraph/selection to a Markdown table.
function M.markdown_table_to_csv()
  utils.map_block(function(lines)
    local md_str = table.concat(lines, '\n')
    local csv_str = utils.markdown_to_csv(md_str)
    vim.fn.setreg('+', csv_str)
    vim.fn.setreg('"', csv_str)
    local csv_lines = {}
    for line in csv_str:gmatch('[^\n]+') do
      table.insert(csv_lines, line)
    end
    return csv_lines
  end)
end

return M
