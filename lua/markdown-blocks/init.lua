--- Module initialisation
local M = {}

--- Checks if the current Vim mode is Visual ('v' or 'V').
--- @return boolean true if in visual mode, false otherwise.
function M.is_visual_mode()
  return vim.fn.mode() == 'v' or vim.fn.mode() == 'V'
end

--- Escapes Vim special regular expression characters plus the `/` character.
--- @param s string The string to escape.
--- @return string The escaped string.
function M.escape_regexp(s)
  return vim.fn.escape(s, '\\/.*$^~[]')
end

--- Adds a local path to Lua's `package.path` for `require`.
--- Allows requiring Lua modules located in the specified directory.
--- @param path string The directory path to prepend to `package.path`.
function M.add_to_path(path)
  -- vim.opt.runtimepath:prepend(path) -- THIS DOESN'T SEEM NECESSARY
  package.path = path .. '/?.lua;' .. path .. '/?/init.lua;' .. package.path
end

--- Reloads all modified buffers from disk.
--- This discards any unsaved changes in those buffers, restoring them
--- to their last saved state. Notifies the user about reloaded files.
function M.reload_modified_buffers()
  local buffers = vim.api.nvim_list_bufs()
  local msgs = {}
  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_option(bufnr, 'modified') then
      local filename = vim.api.nvim_buf_get_name(bufnr)
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd('e!')
      end)
      table.insert(msgs, "Reloaded buffer: " .. filename)
    end
  end
  if #msgs > 0 then
    vim.notify(table.concat(msgs, '\n'))
  end
end

--- Gets the text currently selected in Visual mode.
--- Temporarily yanks the selection to the default register, retrieves it,
--- and then restores the original register content and visual selection state.
--- @return string The visually selected text.
function M.get_visual_selection()
  -- Save the current register content and mode
  local original_register = vim.fn.getreg('"')
  local original_mode = vim.fn.mode()

  -- Yank the selected text into the default register
  vim.cmd('noau normal! "vy')

  -- Retrieve the yanked text from the default register
  local selection = vim.fn.getreg('"')

  -- Restore the original register content
  vim.fn.setreg('"', original_register)

  -- Restore visual mode if it was active
  if original_mode:match('[vV]') then
    vim.cmd('normal! gv')
  end

  return selection
end

--- Gets the current visual selection or the word under the cursor.
--- If in Visual mode (v or V), returns the selection using `M.get_visual_selection`.
--- If in Normal mode (n), returns the word under the cursor (`<cword>`).
--- Returns an empty string in other modes or if `M.get_visual_selection` fails.
--- @return string The selected text or the word under the cursor.
function M.get_selection_or_word()
  local mode = vim.fn.mode()
  local result = ''
  if mode == 'n' then
    result = vim.fn.expand('<cword>')
  elseif mode == 'v' or mode == 'V' then
    result = M.get_visual_selection()
  end
  return result
end

--- Searches for and opens Vim help for a given query.
--- Executes `:help query`. If the command fails (e.g., help topic not found),
--- it shows an error notification.
--- @param query string The help topic to search for.
function M.find_help(query)
  -- Attempt to execute the command with pcall
  local success, _ = pcall(function()
    vim.cmd('help ' .. query)
  end)
  if not success then
    vim.notify("Failed to open help for: " .. query, vim.log.levels.ERROR)
  end
end

--- Toggles the Vim help window.
--- If a help window (`'filetype' == 'help'`) is open, it closes it,
--- remembering the buffer. If no help window is open, it reopens the
--- previously closed help buffer in a split, or opens the default
--- help page (`:help`) if no help buffer was previously remembered.
function M.toggle_help_window()
  -- Track the last help window and buffer
  local last_help = vim.w.last_help or { win = nil, buf = nil }
  -- Check if a help window is currently open
  local help_open = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == 'help' then
      help_open = true
      last_help.win = win
      last_help.buf = buf
      vim.api.nvim_win_close(win, true) -- Close the help window completely
      vim.w.last_help = last_help       -- Save the state of the help buffer
      return
    end
  end
  -- If no help window is open, restore or create a new one
  if not help_open then
    if last_help.buf and vim.api.nvim_buf_is_valid(last_help.buf) then
      vim.cmd('split')                           -- Open a vertical split for the help window
      vim.api.nvim_win_set_buf(0, last_help.buf) -- Restore the previous help buffer
    else
      vim.cmd('help')                            -- Open a new help window if no previous buffer exists
    end
  end
end

--- Adds the current cursor location to the quickfix list.
--- Captures the current filename, line number, column number, and line text
--- and appends it as a new entry to the quickfix list.
function M.add_current_location_to_quickfix()
  local current_file = vim.fn.expand('%:p')
  local current_line = vim.fn.line('.')
  local current_col = vim.fn.col('.')
  local current_text = vim.fn.getline('.')
  local new_item = {
    filename = current_file,
    lnum = current_line,
    col = current_col,
    text = current_text
  }
  local qf_list = vim.fn.getqflist()
  table.insert(qf_list, new_item)
  vim.fn.setqflist(qf_list)
end

--- Deletes the quickfix entry corresponding to the current cursor line in the quickfix window.
--- Removes the item from the quickfix list and updates the list.
--- Attempts to keep the cursor on the same line number or moves it to the
--- preceding item if the last item was deleted. Opens the quickfix window.
function M.delete_current_entry_from_quickfix()
  local ol = vim.fn.line('.')
  local qf = vim.fn.getqflist()
  local ls = #qf
  if ol > 0 and ol <= ls then
    table.remove(qf, ol)
    vim.fn.setqflist(qf, 'r')
    local nls = #qf
    if nls > 0 then
      local tl = math.min(ol, nls)
      vim.cmd('cwindow')
      pcall(vim.api.nvim_win_set_cursor, 0, { tl, 0 })
    else
      vim.cmd('cwindow')
    end
  end
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

--- @diagnostic disable: undefined-doc-param
--- Wraps/unwraps each paragraph in the lines array and returns the updated lines.
--- @param lines string[] The lines to wrap/unwrap.
--- @param opts table Options table with fields:
--- @param opts.column_number number The wrap column number (defaults to 0).
--- @param opts.unwrap boolean Unwrap instead of wrapping (defaults to false).
--- @return string[] The wrapped/unwrapped lines.
function M.wrap_paragraphs(lines, opts)
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
      wrapped_lines = M.wrap_str(joined_text, column_number - #indent)

      -- Indent all lines with the same indent as the first line
      M.indent_lines(wrapped_lines, indent)
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

--- Selects a range of lines in Visual Line mode ('V').
--- Assumes 1-based line numbering.
--- @param start_line number The 1-based starting line number to select.
--- @param end_line number The 1-based ending line number to select.
function M.set_selection(start_line, end_line)
  local cmd = string.format('normal! %dGV%dG', start_line, end_line)
  vim.api.nvim_exec(cmd, false)
end

--- Checks if a given line number marks the end of a paragraph.
--- A line is considered the end of a paragraph if it's the last line
--- in the buffer or if the next line is blank.
--- @param line_number number The 1-based line number to check.
--- @return boolean true if the line is the end of a paragraph, false otherwise.
local function is_end_of_paragraph(line_number)
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
  local mapped_lines = mapfn(lines, { end_of_paragraph = is_end_of_paragraph(end_line) })
  M.set_lines(mapped_lines, start_line, end_line)
end

--- Wraps the current block (visual selection or paragraph).
--- Uses the specified `column_number` or the current cursor column if
--- `column_number` is nil. Preserves indentation of the first line of
--- each paragraph within the block.
--- @param column_number number|nil The 1-based column number to wrap at. Defaults to the current cursor column.
function M.wrap_block(column_number)
  -- Get the cursor column for wrapping
  local col = column_number or vim.fn.col('.')
  M.map_block(function(lines)
    local wrapped_lines = M.wrap_paragraphs(lines, { column_number = col })
    return wrapped_lines
  end)
end

--- Unwraps the current block (visual selection or paragraph).
--- Joins lines within each paragraph of the block into single lines,
--- separated by spaces.
function M.unwrap_block()
  M.map_block(function(lines)
    local joined_lines = M.wrap_paragraphs(lines, { unwrap = true })
    return joined_lines
  end)
end

--- Toggles quoting (prefix '> ') for the current block (visual selection or paragraph).
--- If the first line of the block starts with '> ' then
--- it removes the '> ' prefix from all lines that have it.
--- Otherwise, it prepends '> ' to every line in the block.
function M.quote_block()
  M.map_block(function(lines)
    if lines[1]:match('^>%s') then
      -- If the first line starts with '> ', remove it from this and from any subsequent lines
      for i, line in ipairs(lines) do
        lines[i] = line:gsub('^>%s', '')   -- Remove '> '
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
  M.map_block(function(lines, opts)
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
function M.number_lines(lines)
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
function M.unnumber_lines(lines)
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
function M.renumber_lines(lines)
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
  M.map_block(function(lines)
    if lines[1]:match('^%s*%d+%.%s') then
      M.unnumber_lines(lines)
    else
      M.number_lines(lines)
    end
    return lines
  end)
end

--- Sequentially renumbers existing ordered list items (`N. `) in the current block.
--- Affects the visual selection or the paragraph under the cursor.
--- Respects indentation levels to handle nested lists correctly, using `M.renumber_lines`.
function M.renumber_block()
  M.map_block(function(lines)
    M.renumber_lines(lines)
    return lines
  end)
end

return M
