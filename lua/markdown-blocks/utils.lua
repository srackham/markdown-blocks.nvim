--- Module initialisation
local M = {}

--- Checks if the current Vim mode is Visual ('v' or 'V').
--- @return boolean true if in visual mode, false otherwise.
function M.is_visual_mode()
  return vim.fn.mode() == 'v' or vim.fn.mode() == 'V'
end

--- Prepends an indentation string to each line in a table of strings.
--- Modifies the input table `lines` in place.
--- @param lines table An array of strings representing lines of text.
--- @param indent string The string to prepend to each line.
function M.indent_lines(lines, indent)
  for i, line in ipairs(lines) do
    lines[i] = indent .. line
  end
end

--- Wraps a string `s` at a specified column width.
--- Respects word boundaries. Multiple whitespace characters are collapsed
--- into a single space between words. Effectively trims leading/trailing
--- whitespace from the input string during processing.
--- @param s string The string to wrap.
--- @param wrap_column number The maximum column width for the wrapped lines.
--- @return table An array of strings representing the wrapped lines.
function M.wrap_str(s, wrap_column)
  local result = {} -- Array to store wrapped lines
  local line = ''   -- Current line being built

  -- Iterate through words in the string
  for word in s:gmatch('%S+') do
    -- Check if adding the word exceeds the column limit
    if #line + #word + 1 > wrap_column then
      table.insert(result, line) -- Save the current line
      line = word                -- Start a new line with the current word
    else
      -- Add the word to the current line (with a space if needed)
      if #line > 0 then
        line = line .. ' ' .. word
      else
        line = word
      end
    end
  end

  -- Add any remaining text in the last line to the result
  if #line > 0 then
    table.insert(result, line)
  end

  return result
end

--- Move the cursor with relative row and column numbers.
--- For example `move_cursor(-1, 0)` moves the cursor up one row.
--- Ignore cursor out of bounds errors.
function M.move_cursor(row_delta, col_delta)
  local pos = vim.api.nvim_win_get_cursor(0)
  local new_row = pos[1] + row_delta
  local new_col = pos[2] + col_delta
  pcall(function()
    vim.api.nvim_win_set_cursor(0, { new_row, new_col })
  end)
end

--- Gets the lines spanned by the most recent visual selection.
--- Must be called while in visual mode or immediately after exiting it
--- (it exits visual mode itself to set the '< and '> marks).
--- Shows an error notification if not currently in visual mode.
--- @return table|nil lines An array of strings containing the selected lines, or nil on error.
--- @return number start_line The 1-based start line number of the selection, or 0 on error.
--- @return number end_line The 1-based end line number of the selection, or 0 on error.
function M.get_selected_lines()
  if not M.is_visual_mode() then
    vim.notify('This function must be executed in visual mode', vim.log.levels.ERROR)
    return nil, 0, 0
  end

  -- Exit visual mode (synchronously) to set `<` and `>` marks.
  vim.cmd('normal! ' .. vim.api.nvim_replace_termcodes('<Esc>', true, false, true))

  -- Get the current buffer
  local buf = vim.api.nvim_get_current_buf()

  -- Get the start and end marks of the visual selection
  local start_line = vim.api.nvim_buf_get_mark(buf, '<')[1] -- '<' is the start of the visual selection
  local end_line = vim.api.nvim_buf_get_mark(buf, '>')[1]   -- '>' is the end of the visual selection

  -- Get the lines in the selected range
  local selected_lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)

  -- Return values in the new order: selected_lines, start_line, end_line
  return selected_lines, start_line, end_line
end

--- Gets the lines belonging to the paragraph under the cursor.
--- A paragraph is defined as consecutive non-blank lines surrounded by blank lines
--- or buffer boundaries. Shows an error if the cursor is currently on a blank line.
--- @return table|nil lines An array of strings containing the paragraph lines, or nil on error.
--- @return number start_line The 1-based start line number of the paragraph, or 0 on error.
--- @return number end_line The 1-based end line number of the paragraph, or 0 on error.
function M.get_paragraph()
  -- Check we are not at a blank line
  if vim.api.nvim_get_current_line():match('%S') == nil then
    vim.notify("No paragraph found", vim.log.levels.ERROR)
    return nil, 0, 0
  end

  -- Get the current paragraph's range
  local start_line = vim.fn.search('^\\s*$', 'bW') + 1 -- Find the start line of the paragraph (1-based)
  local end_line = vim.fn.search('^\\s*$', 'W') - 1    -- Find the last line of the paragraph (1-based)

  -- NOTE: vim.fn.search returns 0 if a match is not found (start_line=1, end_line=-1).
  if end_line == -1 then
    end_line = vim.api.nvim_buf_line_count(0) -- Correct end_line
  end


  -- Get all lines in the paragraph
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  return lines, start_line, end_line
end

--- Replaces a range of lines in the current buffer with new lines.
--- Replaces the lines from `start_line` to `end_line` (inclusive, 1-based)
--- with the content of the `lines` table. Sets the cursor position to the
--- beginning of the last inserted line.
--- @param lines table An array of strings to insert.
--- @param start_line number The 1-based starting line number of the range to replace.
--- @param end_line number The 1-based ending line number of the range to replace.
function M.set_lines(lines, start_line, end_line)
  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, lines)
  local cursor_line = start_line + #lines - 1
  vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })
end

--- Checks if a given line number marks the end of a paragraph.
--- A line is considered the end of a paragraph if it's the last line
--- in the buffer or if the next line is blank.
--- @param line_number number The 1-based line number to check.
--- @return boolean true if the line is the end of a paragraph, false otherwise.
function M.is_end_of_paragraph(line_number)
  local total_lines = vim.api.nvim_buf_line_count(0)

  -- Case 1: Already at last line
  if line_number == total_lines then
    return true
  end

  -- Case 2: Check next line for blankness
  local next_line = vim.api.nvim_buf_get_lines(
    0,               -- current buffer
    line_number,     -- 0-based start (next line in 1-based)
    line_number + 1, -- 0-based end (exclusive)
    false            -- strict indexing
  )[1] or ''         -- handle missing lines gracefully
  return next_line == ''
end

--- Applies a mapping function to the current block (visual selection or paragraph).
--- Determines the block (visual selection if active, otherwise the paragraph
--- under the cursor). Retrieves the lines of the block. Calls `mapfn` with
--- the lines and an options table `{ end_of_paragraph = boolean }`.
--- If end_of_paragraph=true then the last line is the last line of a paragraph.
--- Replaces the original lines in the buffer with the lines returned by `mapfn`.
--- @param mapfn function The function to apply. It receives two parameters (lines, options) and must return a table of strings (the modified lines).
function M.map_block(mapfn)
  local lines, start_line, end_line
  if M.is_visual_mode() then
    lines, start_line, end_line = M.get_selected_lines()
  else
    lines, start_line, end_line = M.get_paragraph()
  end
  if lines == nil then
    return
  end
  local mapped_lines = mapfn(lines, { end_of_paragraph = M.is_end_of_paragraph(end_line) })
  M.set_lines(mapped_lines, start_line, end_line)
  M.move_cursor(1, 0) -- Move cursor down one to the line after the inserted block
end

function M.parse_csv_line(line)
  local res = {}
  local i = 1
  local len = #line
  while i <= len do
    local c = line:sub(i, i)
    local field = ""
    if c == '"' then
      -- Quoted field
      i = i + 1
      while i <= len do
        c = line:sub(i, i)
        if c == '"' then
          if line:sub(i + 1, i + 1) == '"' then
            -- Escaped quote ("")
            field = field .. '"'
            i = i + 2
          else
            -- End of quoted field
            i = i + 1
            break
          end
        else
          field = field .. c
          i = i + 1
        end
      end
      -- Skip optional whitespace and comma after quoted field
      while i <= len and line:sub(i, i):match("[%s,]") do
        if line:sub(i, i) == ',' then
          i = i + 1
          break
        end
        i = i + 1
      end
    else
      -- Unquoted field
      while i <= len and line:sub(i, i) ~= ',' do
        field = field .. line:sub(i, i)
        i = i + 1
      end
      -- Skip comma after field, if present
      if line:sub(i, i) == ',' then
        i = i + 1
      end
      -- Trim whitespace
      field = field:match("^%s*(.-)%s*$")
    end
    table.insert(res, field)
  end
  return res
end

--- Convert a CSV string to a Markdown table.
-- Assumes the first line contains headers. Handles fields optionally quoted with double quotes.
-- @param csv string: The CSV data as a string.
-- @return string: The resulting Markdown table as a string.
function M.csv_to_markdown(csv)
  local lines = {}
  for line in csv:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end

  if #lines == 0 then
    return ""
  end

  local header = M.parse_csv_line(lines[1])
  local markdown = "| " .. table.concat(header, " | ") .. " |\n"
  markdown = markdown .. "|" .. string.rep("---|", #header) .. "\n"

  for i = 2, #lines do
    local row = M.parse_csv_line(lines[i])
    markdown = markdown .. "| " .. table.concat(row, " | ") .. " |\n"
  end

  return markdown
end

--- Convert a Markdown table string to CSV.
-- @param Markdown: The Markdown table as a string.
-- @return string: The resulting CSV as a string.
function M.markdown_to_csv(md)
  local csv_lines = {}
  local lines = {}
  -- Split the input into lines
  for line in md:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  -- Process each relevant line
  for i, line in ipairs(lines) do
    -- Skip the separator (second line)
    if i ~= 2 then
      -- Remove leading/trailing pipes and whitespace
      line = line:gsub("^%s*|", ""):gsub("|%s*$", "")
      -- Split by pipes
      local cells = {}
      for cell in line:gmatch("[^|]+") do
        -- Trim whitespace from cell
        cell = cell:match("^%s*(.-)%s*$")
        -- Escape double quotes and wrap in double quotes
        cell = '"' .. cell:gsub('"', '""') .. '"'
        table.insert(cells, cell)
      end
      -- Concatenate cells with commas
      table.insert(csv_lines, table.concat(cells, ","))
    end
  end
  -- Join lines with newlines
  return table.concat(csv_lines, "\n")
end

return M
