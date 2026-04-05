local api_base_url = "https://ipod-2to6magyna-uc.a.run.app/"
local version = "2.1"

local width, height = term.getSize()
local tab = 1

local theme = {
	bg = colors.black,
	tab_bg = colors.gray,
	tab_active_bg = colors.green,
	tab_text = colors.white,
	tab_active_text = colors.black,
	primary = colors.white,
	secondary = colors.gray,
	accent = colors.green,
	button_bg = colors.green,
	button_active_bg = colors.white,
	button_text = colors.black,
	muted_button_text = colors.black,
	disabled_bg = colors.gray,
	search_box_bg = colors.gray,
	search_box_active_bg = colors.white,
	error = colors.red
}

local waiting_for_input = false
local last_search = nil
local last_search_url = nil
local search_results = nil
local search_error = false
local search_scroll = 0
local in_search_result = false
local clicked_result = nil
local playlist_files = {}
local playlist_scroll = 0
local in_playlist_result = false
local clicked_playlist = nil
local clicked_playlist_items = nil
local playlist_error = nil
local input_mode = nil

local playing = false
local queue = {}
local now_playing = nil
local looping = 0
local volume = 1.5

local playing_id = nil
local last_download_url = nil
local playing_status = 0
local is_loading = false
local is_error = false;

local player_handle = nil
local start = nil
local pcm = nil
local size = nil
local decoder = require "cc.audio.dfpwm".make_decoder()
local needs_next_chunk = 0
local buffer

local speakers = { peripheral.find("speaker") }
if #speakers == 0 then
	error("No speakers attached. You need to connect a speaker to this computer. If this is an Advanced Noisy Pocket Computer, then this is a bug, and you should try restarting your Minecraft game.", 0)
end
math.randomseed(os.epoch("utc"))

local function ccText(value, max_len)
	local text = tostring(value or "")

	-- Strip emoji variation selector and map common emoji/symbols to ComputerCraft-safe glyphs.
	text = text:gsub(string.char(239, 184, 143), "")
	text = text:gsub(string.char(240, 159, 142, 181), string.char(14)) -- 🎵 -> ♪
	text = text:gsub(string.char(240, 159, 142, 182), string.char(15)) -- 🎶 -> ♫
	text = text:gsub(string.char(226, 153, 171), string.char(15)) -- ♫
	text = text:gsub(string.char(226, 153, 170), string.char(14)) -- ♪
	text = text:gsub(string.char(226, 157, 164), string.char(3)) -- ❤ -> ♥
	text = text:gsub(string.char(240, 159, 146, 153), string.char(3)) -- 💙 -> ♥
	text = text:gsub(string.char(240, 159, 146, 154), string.char(3)) -- 💚 -> ♥
	text = text:gsub(string.char(240, 159, 146, 155), string.char(3)) -- 💛 -> ♥
	text = text:gsub(string.char(240, 159, 167, 161), string.char(3)) -- 🧡 -> ♥
	text = text:gsub(string.char(240, 159, 146, 156), string.char(3)) -- 💜 -> ♥
	text = text:gsub(string.char(240, 159, 150, 164), string.char(16)) -- ▶ -> ►
	text = text:gsub(string.char(226, 143, 173), string.char(187)) -- ⏭ -> »
	text = text:gsub(string.char(226, 143, 184), "[]") -- ⏸ -> []
	text = text:gsub(string.char(240, 159, 148, 128), "<>") -- 🔀
	text = text:gsub(string.char(240, 159, 148, 129), "(Q)") -- 🔁
	text = text:gsub(string.char(240, 159, 148, 130), "(1)") -- 🔂

	-- Common punctuation normalization.
	text = text:gsub(string.char(226, 128, 152), "'")
	text = text:gsub(string.char(226, 128, 153), "'")
	text = text:gsub(string.char(226, 128, 156), "\"")
	text = text:gsub(string.char(226, 128, 157), "\"")
	text = text:gsub(string.char(226, 128, 166), "...")
	text = text:gsub(string.char(226, 128, 147), "-")
	text = text:gsub(string.char(226, 128, 148), "-")

	-- Keep display stable in fixed-width UI.
	text = text:gsub("[%c]", " ")
	if max_len and max_len > 0 and #text > max_len then
		text = string.sub(text, 1, max_len)
	end
	return text
end

function redrawScreen()
	if waiting_for_input then
		return
	end

	term.setCursorBlink(false)  -- Make sure cursor is off when redrawing
	-- Clear the screen
	term.setBackgroundColor(theme.bg)
	term.clear()

	--Draw the three top tabs
	term.setCursorPos(1,1)
	term.setBackgroundColor(theme.tab_bg)
	term.clearLine()
	
	local tabs = {" Now Playing ", " Search ", " Playlists "}
	
	for i=1,#tabs,1 do
		if tab == i then
			term.setTextColor(theme.tab_active_text)
			term.setBackgroundColor(theme.tab_active_bg)
		else
			term.setTextColor(theme.tab_text)
			term.setBackgroundColor(theme.tab_bg)
		end
		
		term.setCursorPos((math.floor((width/#tabs)*(i-0.5)))-math.ceil(#tabs[i]/2)+1, 1)
		term.write(tabs[i])
	end

	if tab == 1 then
		drawNowPlaying()
	elseif tab == 2 then
		drawSearch()
	elseif tab == 3 then
		drawPlaylists()
	end
end

function getVisibleSearchRows()
	return math.max(0, math.floor((height - 6) / 2))
end

function getMaxSearchScroll()
	if search_results == nil then
		return 0
	end
	return math.max(0, #search_results - getVisibleSearchRows())
end

function normalizeSearchResults(payload)
	if type(payload) ~= "table" then
		return {}
	end
	if payload[1] ~= nil then
		return payload
	end
	if type(payload.results) == "table" then
		return payload.results
	end
	if type(payload.items) == "table" then
		return payload.items
	end
	return {}
end

function getVisiblePlaylistRows()
	return math.max(0, height - getPlaylistListStartY() + 1)
end

function getPlaylistListStartY()
	return 8
end

function getMaxPlaylistScroll()
	return math.max(0, #playlist_files - getVisiblePlaylistRows())
end

function refreshPlaylists()
	playlist_files = {}
	for _, name in ipairs(fs.list(".")) do
		if string.sub(name, -4) == ".mpl" and not fs.isDir(name) then
			table.insert(playlist_files, name)
		end
	end
	table.sort(playlist_files)
	playlist_scroll = math.max(0, math.min(playlist_scroll, getMaxPlaylistScroll()))
end

function sanitizePlaylistFileName(name)
	local trimmed = string.match(name or "", "^%s*(.-)%s*$") or ""
	if trimmed == "" then
		return nil
	end
	trimmed = string.gsub(trimmed, "[%c/\\:*?\"<>|]", "_")
	if string.sub(trimmed, -4) ~= ".mpl" then
		trimmed = trimmed .. ".mpl"
	end
	return trimmed
end

function snapshotCurrentPlayableItems()
	local items = {}
	if now_playing ~= nil and now_playing.id ~= nil then
		table.insert(items, {
			id = tostring(now_playing.id),
			name = now_playing.name or "Unknown title",
			artist = now_playing.artist or "Unknown artist",
			type = "song"
		})
	end
	for i=1,#queue do
		if queue[i] and queue[i].id ~= nil then
			table.insert(items, {
				id = tostring(queue[i].id),
				name = queue[i].name or ("Track " .. tostring(i)),
				artist = queue[i].artist or "Unknown artist",
				type = "song"
			})
		end
	end
	return items
end

function writePlaylistFile(path, items)
	local handle = fs.open(path, "w")
	if not handle then
		return false, "Unable to write file"
	end
	handle.write(textutils.serialiseJSON({items = items}))
	handle.close()
	return true, nil
end

function saveQueueToPlaylist(path)
	local items = snapshotCurrentPlayableItems()
	if #items == 0 then
		return false, "Nothing in current queue to save"
	end
	return writePlaylistFile(path, items)
end

function deletePlaylistFile(path)
	if not fs.exists(path) then
		return false, "Playlist file not found"
	end
	fs.delete(path)
	return true, nil
end

function normalizePlaylistItems(payload)
	local results = {}
	if type(payload) ~= "table" then
		return results
	end

	local source = payload
	if payload[1] == nil then
		if type(payload.items) == "table" then
			source = payload.items
		elseif type(payload.songs) == "table" then
			source = payload.songs
		else
			source = {}
		end
	end

	for i=1,#source do
		local item = source[i]
		if type(item) == "table" and item.id then
			table.insert(results, {
				id = tostring(item.id),
				name = item.name or ("Track " .. tostring(i)),
				artist = item.artist or "Unknown artist",
				type = "song"
			})
		end
	end
	return results
end

function parsePlaylistContent(content)
	if type(content) ~= "string" or content == "" then
		return {}
	end

	local parsed_json = textutils.unserialiseJSON(content)
	local items = normalizePlaylistItems(parsed_json)
	if #items > 0 then
		return items
	end

	local parsed_lua = textutils.unserialize(content)
	items = normalizePlaylistItems(parsed_lua)
	if #items > 0 then
		return items
	end

	for line in string.gmatch(content, "[^\r\n]+") do
		local id, name, artist = string.match(line, "^([^|]+)|([^|]+)|(.+)$")
		if id then
			table.insert(items, {
				id = tostring(id),
				name = name,
				artist = artist,
				type = "song"
			})
		else
			local only_id = string.match(line, "^%s*([^%s]+)%s*$")
			if only_id and only_id ~= "" then
				table.insert(items, {
					id = tostring(only_id),
					name = "Unknown title",
					artist = "Unknown artist",
					type = "song"
				})
			end
		end
	end
	return items
end

function loadPlaylistFile(path)
	local handle = fs.open(path, "r")
	if not handle then
		return nil, "Unable to open file"
	end
	local content = handle.readAll()
	handle.close()

	local items = parsePlaylistContent(content)
	if #items == 0 then
		return nil, "No playable songs found"
	end
	return items, nil
end

function applyPlaylistNow(items)
	for _, speaker in ipairs(speakers) do
		speaker.stop()
		os.queueEvent("playback_stopped")
	end
	now_playing = items[1]
	queue = {}
	for i=2,#items do
		table.insert(queue, items[i])
	end
	playing = true
	is_error = false
	playing_id = nil
	is_loading = false
	os.queueEvent("audio_update")
end

function appendPlaylistQueue(items)
	for i=1,#items do
		table.insert(queue, items[i])
	end
	if now_playing == nil then
		now_playing = queue[1]
		table.remove(queue, 1)
	end
	is_error = false
	os.queueEvent("audio_update")
end

function moveQueueItem(from_index, to_index)
	if from_index < 1 or from_index > #queue or to_index < 1 or to_index > #queue then
		return false
	end
	if from_index == to_index then
		return false
	end
	local item = queue[from_index]
	table.remove(queue, from_index)
	table.insert(queue, to_index, item)
	return true
end

function shuffleQueueInPlace()
	for i=#queue,2,-1 do
		local j = math.random(i)
		queue[i], queue[j] = queue[j], queue[i]
	end
end

function drawNowPlaying()
	if now_playing ~= nil then
		term.setBackgroundColor(theme.bg)
		term.setTextColor(theme.primary)
		term.setCursorPos(2,3)
		term.write(ccText(now_playing.name, math.max(1, width - 2)))
		term.setTextColor(theme.secondary)
		term.setCursorPos(2,4)
		term.write(ccText(now_playing.artist, math.max(1, width - 2)))
	else
		term.setBackgroundColor(theme.bg)
		term.setTextColor(theme.secondary)
		term.setCursorPos(2,3)
		term.write("Not playing")
	end

	if is_loading == true then
		term.setTextColor(theme.secondary)
		term.setBackgroundColor(theme.bg)
		term.setCursorPos(2,5)
		term.write("Loading...")
	elseif is_error == true then
		term.setTextColor(theme.error)
		term.setBackgroundColor(theme.bg)
		term.setCursorPos(2,5)
		term.write("Network error")
	end

	term.setTextColor(theme.button_text)
	term.setBackgroundColor(theme.button_bg)

	if playing then
		term.setCursorPos(2, 6)
		term.write(" [] ")
	else
			if now_playing ~= nil or #queue > 0 then
				term.setTextColor(theme.button_text)
				term.setBackgroundColor(theme.button_bg)
			else
				term.setTextColor(theme.muted_button_text)
				term.setBackgroundColor(theme.disabled_bg)
			end
		term.setCursorPos(2, 6)
		term.write(" " .. string.char(16) .. " ")
	end

	if now_playing ~= nil or #queue > 0 then
		term.setTextColor(theme.button_text)
		term.setBackgroundColor(theme.button_bg)
	else
		term.setTextColor(theme.muted_button_text)
		term.setBackgroundColor(theme.disabled_bg)
	end
	term.setCursorPos(7, 6)
	term.write(" " .. string.char(187) .. " ")

	if looping ~= 0 then
		term.setTextColor(theme.button_text)
		term.setBackgroundColor(theme.button_active_bg)
	else
		term.setTextColor(theme.button_text)
		term.setBackgroundColor(theme.button_bg)
	end
	term.setCursorPos(12, 6)
	if looping == 0 then
		term.write(" ( ) ")
	elseif looping == 1 then
		term.write(" (Q) ")
	else
		term.write(" (1) ")
	end

	term.setTextColor(theme.button_text)
	term.setBackgroundColor(theme.button_bg)
	term.setCursorPos(18,6)
	term.write(" <> ")

	term.setCursorPos(2,8)
	paintutils.drawBox(2,8,25,8,theme.button_bg)
	local volume_width = math.floor(24 * (volume / 3) + 0.5)-1
	if not (volume_width == -1) then
		paintutils.drawBox(2,8,2+volume_width,8,theme.button_active_bg)
	end
	if volume < 0.6 then
		term.setCursorPos(2+volume_width+2,8)
		term.setBackgroundColor(theme.button_bg)
		term.setTextColor(theme.button_text)
	else
		term.setCursorPos(2+volume_width-3-(volume == 3 and 1 or 0),8)
		term.setBackgroundColor(theme.button_active_bg)
		term.setTextColor(theme.button_text)
	end
	term.write(math.floor(100 * (volume / 3) + 0.5) .. "%")

	if #queue > 0 then
		term.setBackgroundColor(theme.bg)
		for i=1,#queue do
			local name_y = 10 + (i-1)*2
			local artist_y = 11 + (i-1)*2
			if artist_y > height then
				break
			end
			local name_max = math.max(1, width - 3)
			local artist_max = math.max(1, width - 3)
			local song_name = ccText(queue[i].name or "Unknown title", name_max)
			local artist_name = ccText(queue[i].artist or "Unknown artist", artist_max)
			term.setTextColor(theme.primary)
			term.setCursorPos(2,name_y)
			term.write(song_name)
			term.setTextColor(theme.secondary)
			term.setCursorPos(2,artist_y)
			term.write(artist_name)
			term.setTextColor(theme.accent)
			term.setCursorPos(width - 1, name_y)
			term.write(i > 1 and "^" or " ")
			term.setCursorPos(width, name_y)
			term.write(i < #queue and "v" or " ")
			term.setCursorPos(width - 1, artist_y)
			term.write("x")
			term.setCursorPos(width, artist_y)
			term.write(" ")
		end
	end
end

function drawSearch()
	-- Search bar
	paintutils.drawFilledBox(2,3,width-1,5,theme.search_box_bg)
	term.setBackgroundColor(theme.search_box_bg)
	term.setCursorPos(3,4)
	term.setTextColor(theme.primary)
	term.write(ccText(last_search or "Search...", math.max(1, width - 3)))

	--Search results
	if search_results ~= nil then
		term.setBackgroundColor(theme.bg)
		local visible_rows = getVisibleSearchRows()
		local first_index = search_scroll + 1
		local last_index = math.min(#search_results, first_index + visible_rows - 1)
		for i=first_index,last_index do
			local slot = i - first_index
			if i == 1 then
				term.setTextColor(colors.lime)
			else
				term.setTextColor(theme.primary)
			end
			term.setCursorPos(2,7 + slot*2)
			term.write(ccText(search_results[i].name, math.max(1, width - 2)))
			if i == 1 then
				term.setTextColor(colors.green)
			else
				term.setTextColor(theme.secondary)
			end
			term.setCursorPos(2,8 + slot*2)
			term.write(ccText(search_results[i].artist, math.max(1, width - 2)))
		end
		if #search_results > visible_rows then
			term.setTextColor(theme.accent)
			term.setBackgroundColor(theme.bg)
			if search_scroll > 0 then
				term.setCursorPos(width, 7)
				term.write("^")
			end
			if search_scroll < getMaxSearchScroll() then
				term.setCursorPos(width, height)
				term.write("v")
			end
		end
	else
		term.setCursorPos(2,7)
		term.setBackgroundColor(theme.bg)
		if search_error == true then
			term.setTextColor(theme.error)
			term.write("Network error")
		elseif last_search_url ~= nil then
			term.setTextColor(theme.secondary)
			term.write("Searching...")
		else
			term.setCursorPos(1,7)
			term.setTextColor(theme.secondary)
			print("Tip: You can paste YouTube video or playlist links.")
		end
	end

	--fullscreen song options
	if in_search_result == true then
		term.setBackgroundColor(theme.bg)
		term.clear()
		term.setCursorPos(2,2)
		term.setTextColor(theme.primary)
		term.write(ccText(search_results[clicked_result].name, math.max(1, width - 2)))
		term.setCursorPos(2,3)
		term.setTextColor(theme.secondary)
		term.write(ccText(search_results[clicked_result].artist, math.max(1, width - 2)))

		term.setBackgroundColor(theme.button_bg)
		term.setTextColor(theme.button_text)

		term.setCursorPos(2,6)
		term.clearLine()
		term.write("Play now")

		term.setCursorPos(2,8)
		term.clearLine()
		term.write("Play next")

		term.setCursorPos(2,10)
		term.clearLine()
		term.write("Add to queue")

		term.setCursorPos(2,13)
		term.clearLine()
		term.write("Cancel")
	end
end

function drawPlaylists()
	if in_playlist_result then
		term.setBackgroundColor(theme.bg)
		term.clear()
		term.setCursorPos(2,2)
		term.setTextColor(theme.primary)
		term.write(ccText(clicked_playlist or "Playlist", math.max(1, width - 2)))
		term.setCursorPos(2,3)
		term.setTextColor(theme.secondary)
		term.write(tostring(#clicked_playlist_items) .. " tracks")

		term.setBackgroundColor(theme.button_bg)
		term.setTextColor(theme.button_text)

		term.setCursorPos(2,6)
		term.clearLine()
		term.write("Play now")

		term.setCursorPos(2,8)
		term.clearLine()
		term.write("Add to queue")

		term.setCursorPos(2,10)
		term.clearLine()
		term.write("Delete playlist")

		term.setCursorPos(2,12)
		term.clearLine()
		term.write("Cancel")
		return
	end

	refreshPlaylists()
	term.setBackgroundColor(theme.bg)
	term.setCursorPos(2,3)
	term.setTextColor(theme.secondary)
	term.write("Saved .mpl playlists")

	term.setBackgroundColor(theme.button_bg)
	term.setTextColor(theme.button_text)
	term.setCursorPos(2,5)
	if #queue > 0 then
		term.write(" Save Queue ")
	else
		term.setBackgroundColor(theme.disabled_bg)
		term.setTextColor(colors.black)
		term.write("Create a queue to create a playlist!")
	end

	if playlist_error then
		term.setCursorPos(2,4)
		term.setTextColor(theme.error)
		term.write(ccText(playlist_error, math.max(1, width - 2)))
	end

	if #playlist_files == 0 then
		term.setCursorPos(2,getPlaylistListStartY())
		term.setTextColor(theme.secondary)
		term.write("No .mpl files found in this folder.")
		return
	end

	local visible_rows = getVisiblePlaylistRows()
	local first_index = playlist_scroll + 1
	local last_index = math.min(#playlist_files, first_index + visible_rows - 1)
	for i=first_index,last_index do
		local y = getPlaylistListStartY() + (i - first_index)
		term.setCursorPos(2, y)
		term.setTextColor(theme.primary)
		term.write(ccText(playlist_files[i], math.max(1, width - 2)))
	end

	if #playlist_files > visible_rows then
		term.setTextColor(theme.accent)
		if playlist_scroll > 0 then
			term.setCursorPos(width, getPlaylistListStartY())
			term.write("^")
		end
		if playlist_scroll < getMaxPlaylistScroll() then
			term.setCursorPos(width, height)
			term.write("v")
		end
	end
end

function uiLoop()
	redrawScreen()

	while true do
		if waiting_for_input then
			parallel.waitForAny(
				function()
						if input_mode == "search" then
							term.setCursorPos(3,4)
							term.setBackgroundColor(colors.white)
							term.setTextColor(colors.black)
						elseif input_mode == "playlist_name" then
							term.setCursorPos(3,5)
							term.setBackgroundColor(colors.white)
							term.setTextColor(colors.black)
						end
						local input = read()
	
						if input_mode == "search" then
							if string.len(input) > 0 then
								last_search = input
								last_search_url = api_base_url .. "?v=" .. version .. "&search=" .. textutils.urlEncode(input)
								http.request(last_search_url)
								search_results = nil
								search_error = false
								search_scroll = 0
							else
								last_search = nil
								last_search_url = nil
								search_results = nil
								search_error = false
								search_scroll = 0
							end
							elseif input_mode == "playlist_name" and string.len(input) > 0 then
								local file_name = sanitizePlaylistFileName(input)
								if file_name == nil then
									playlist_error = "Invalid playlist name"
								else
									local ok, err = saveQueueToPlaylist(file_name)
									if ok then
										playlist_error = "Saved queue to " .. file_name
									end
									if not ok then
										playlist_error = err
									end
									refreshPlaylists()
							end
						end
	
							waiting_for_input = false
							input_mode = nil
							os.queueEvent("redraw_screen")
						end,
					function()
						while waiting_for_input do
							local event, button, x, y = os.pullEvent("mouse_click")
							local in_box = false
							if input_mode == "search" then
								in_box = y >= 3 and y <= 5 and x >= 2 and x <= width-1
							elseif input_mode == "playlist_name" then
								in_box = y == 5 and x >= 2 and x <= width-1
							end
								if not in_box then
									waiting_for_input = false
									input_mode = nil
									os.queueEvent("redraw_screen")
									break
								end
						end
				end
			)
		else
			parallel.waitForAny(
				function()
					local event, button, x, y = os.pullEvent("mouse_click")

						if button == 1 then
							-- Tabs
							if in_search_result == false and in_playlist_result == false then
								if y == 1 then
									local tabs_count = 3
									local tab_width = width / tabs_count
									tab = math.max(1, math.min(tabs_count, math.ceil(x / tab_width)))
									if tab == 3 then
										refreshPlaylists()
										playlist_error = nil
									end
									redrawScreen()
								end
							end
						
							if tab == 2 and in_search_result == false then
							-- Search box click
								if y >= 3 and y <= 5 and x >= 1 and x <= width-1 then
									paintutils.drawFilledBox(2,3,width-1,5,theme.search_box_active_bg)
									term.setBackgroundColor(theme.search_box_active_bg)
									waiting_for_input = true
									input_mode = "search"
								end
		
							-- Search result click
							if search_results then
								local visible_rows = getVisibleSearchRows()
								local first_index = search_scroll + 1
								local row = math.floor((y - 7) / 2)
								local result_index = first_index + row
								local in_result_bounds = y >= 7 and y <= (7 + visible_rows * 2 - 1)
								if in_result_bounds and result_index >= first_index and result_index <= #search_results then
										local slot = result_index - first_index
										term.setBackgroundColor(theme.button_active_bg)
										term.setTextColor(theme.button_text)
										term.setCursorPos(2,7 + slot*2)
										term.clearLine()
										term.write(ccText(search_results[result_index].name, math.max(1, width - 2)))
										term.setTextColor(theme.secondary)
										term.setCursorPos(2,8 + slot*2)
										term.clearLine()
										term.write(ccText(search_results[result_index].artist, math.max(1, width - 2)))
										sleep(0.2)
										in_search_result = true
										clicked_result = result_index
										redrawScreen()
								end
							end
						elseif tab == 2 and in_search_result == true then
							-- Search result menu clicks
		
							term.setBackgroundColor(theme.button_active_bg)
							term.setTextColor(theme.button_text)
		
								if y == 6 then
								term.setCursorPos(2,6)
								term.clearLine()
								term.write("Play now")
								sleep(0.2)
								in_search_result = false
								for _, speaker in ipairs(speakers) do
									speaker.stop()
									os.queueEvent("playback_stopped")
								end
								playing = true
								is_error = false
								playing_id = nil
									if search_results[clicked_result].type == "playlist" then
										now_playing = search_results[clicked_result].playlist_items[1]
										queue = {}
										if #search_results[clicked_result].playlist_items > 1 then
											for i=2, #search_results[clicked_result].playlist_items do
												table.insert(queue, search_results[clicked_result].playlist_items[i])
											end
										end
									else
										now_playing = search_results[clicked_result]
									end
									os.queueEvent("audio_update")
								end
		
							if y == 8 then
								term.setCursorPos(2,8)
								term.clearLine()
								term.write("Play next")
								sleep(0.2)
								in_search_result = false
									if search_results[clicked_result].type == "playlist" then
										for i = #search_results[clicked_result].playlist_items, 1, -1 do
											table.insert(queue, 1, search_results[clicked_result].playlist_items[i])
										end
									else
										table.insert(queue, 1, search_results[clicked_result])
									end
									os.queueEvent("audio_update")
								end
		
							if y == 10 then
								term.setCursorPos(2,10)
								term.clearLine()
								term.write("Add to queue")
								sleep(0.2)
								in_search_result = false
									if search_results[clicked_result].type == "playlist" then
										for i = 1, #search_results[clicked_result].playlist_items do
											table.insert(queue, search_results[clicked_result].playlist_items[i])
										end
									else
										table.insert(queue, search_results[clicked_result])
									end
									os.queueEvent("audio_update")
								end
		
							if y == 13 then
								term.setCursorPos(2,13)
								term.clearLine()
								term.write("Cancel")
								sleep(0.2)
								in_search_result = false
							end
		
							redrawScreen()
							elseif tab == 3 and in_playlist_result == false then
								if #queue > 0 and y == 5 and x >= 2 and x <= 13 then
									paintutils.drawFilledBox(2,5,width-1,5,theme.search_box_active_bg)
									term.setBackgroundColor(theme.search_box_active_bg)
									term.setTextColor(theme.primary)
									term.setCursorPos(3,5)
									term.clearLine()
									term.write("Save queue as...")
									waiting_for_input = true
									input_mode = "playlist_name"
								end
								if #playlist_files > 0 then
									local visible_rows = getVisiblePlaylistRows()
									local first_index = playlist_scroll + 1
									local row = y - getPlaylistListStartY()
									local index = first_index + row
									if row >= 0 and row < visible_rows and index >= first_index and index <= #playlist_files then
										local file = playlist_files[index]
									local items, err = loadPlaylistFile(file)
									if items then
										in_playlist_result = true
										clicked_playlist = file
										clicked_playlist_items = items
										playlist_error = nil
									else
										playlist_error = err
									end
									redrawScreen()
								end
							end
						elseif tab == 3 and in_playlist_result == true then
							term.setBackgroundColor(theme.button_active_bg)
							term.setTextColor(theme.button_text)

							if y == 6 then
								term.setCursorPos(2,6)
								term.clearLine()
								term.write("Play now")
								sleep(0.2)
								in_playlist_result = false
								applyPlaylistNow(clicked_playlist_items)
							end

							if y == 8 then
								term.setCursorPos(2,8)
								term.clearLine()
								term.write("Add to queue")
								sleep(0.2)
								in_playlist_result = false
								appendPlaylistQueue(clicked_playlist_items)
							end

								if y == 10 then
									term.setCursorPos(2,10)
									term.clearLine()
									term.write("Delete playlist")
									sleep(0.2)
									local ok, err = deletePlaylistFile(clicked_playlist)
									if ok then
										playlist_error = "Deleted " .. clicked_playlist
										in_playlist_result = false
										clicked_playlist = nil
										clicked_playlist_items = nil
										refreshPlaylists()
									else
										playlist_error = err
									end
								end

								if y == 12 then
									term.setCursorPos(2,12)
									term.clearLine()
									term.write("Cancel")
									sleep(0.2)
									in_playlist_result = false
								end
								redrawScreen()
						elseif tab == 1 and in_search_result == false then
							-- Now playing tab clicks
		
							if y == 6 then
								-- Play/stop button
								if x >= 2 and x < 6 then
									if playing or now_playing ~= nil or #queue > 0 then
										term.setBackgroundColor(colors.white)
										term.setTextColor(colors.black)
											term.setCursorPos(2, 6)
											if playing then
												term.write(" [] ")
											else 
												term.write(" " .. string.char(16) .. " ")
											end
										sleep(0.2)
									end
									if playing then
										playing = false
										for _, speaker in ipairs(speakers) do
											speaker.stop()
											os.queueEvent("playback_stopped")
										end
										playing_id = nil
										is_loading = false
										is_error = false
										os.queueEvent("audio_update")
									elseif now_playing ~= nil then
										playing_id = nil
										playing = true
										is_error = false
										os.queueEvent("audio_update")
									elseif #queue > 0 then
										now_playing = queue[1]
										table.remove(queue, 1)
										playing_id = nil
										playing = true
										is_error = false
										os.queueEvent("audio_update")
									end
								end
		
								-- Skip button
								if x >= 7 and x < 11 then
									if now_playing ~= nil or #queue > 0 then
										term.setBackgroundColor(colors.white)
										term.setTextColor(colors.black)
										term.setCursorPos(7, 6)
										term.write(" " .. string.char(187) .. " ")
										sleep(0.2)
		
										is_error = false
										if playing then
											for _, speaker in ipairs(speakers) do
												speaker.stop()
												os.queueEvent("playback_stopped")
											end
										end
											if #queue > 0 then
												if looping == 1 then
													table.insert(queue, now_playing)
												end
												now_playing = queue[1]
												table.remove(queue, 1)
												playing_id = nil
										else
											now_playing = nil
											playing = false
											is_loading = false
											is_error = false
											playing_id = nil
										end
										os.queueEvent("audio_update")
									end
								end
		
								-- Loop button
								if x >= 12 and x < 17 then
									if looping == 0 then
										looping = 1
									elseif looping == 1 then
										looping = 2
									else
										looping = 0
									end
								end

								-- Shuffle button (one-shot queue shuffle)
								if x >= 18 and x < 22 then
									shuffleQueueInPlace()
								end
							end

								if y == 8 then
								-- Volume slider
								if x >= 1 and x < 2 + 24 then
									volume = (x - 1) / 24 * 3

									-- for _, speaker in ipairs(speakers) do
									-- 	speaker.stop()
									-- 	os.queueEvent("playback_stopped")
									-- end
										-- playing_id = nil
										-- os.queueEvent("audio_update")
									end
								end

								if #queue > 0 and y >= 10 and y <= (11 + (#queue - 1) * 2) then
									local queue_index = math.floor((y - 10) / 2) + 1
									local is_artist_row = ((y - 10) % 2) == 1

									if not is_artist_row and (x == width - 1 or x == width) then
										if x == width - 1 then
											moveQueueItem(queue_index, queue_index - 1)
										else
											moveQueueItem(queue_index, queue_index + 1)
										end
									end

									if is_artist_row and (x == width - 1 or x == width) then
										table.remove(queue, queue_index)
									end
								end

								redrawScreen()
							end
					end
				end,
				function()
					local event, button, x, y = os.pullEvent("mouse_drag")

					if button == 1 then

						if tab == 1 and in_search_result == false then

								if y == 8 then
								-- Volume slider
								if x >= 1 and x < 2 + 24 then
									volume = (x - 1) / 24 * 3

									-- for _, speaker in ipairs(speakers) do
									-- 	speaker.stop()
									-- 	os.queueEvent("playback_stopped")
									-- end
									-- playing_id = nil
									-- os.queueEvent("audio_update")
								end
							end

							redrawScreen()
						end
					end
				end,
					function()
						local event, direction, x, y = os.pullEvent("mouse_scroll")
						if tab == 2 and in_search_result == false and search_results ~= nil and y >= 7 then
							local max_scroll = getMaxSearchScroll()
							if max_scroll > 0 then
								search_scroll = math.max(0, math.min(max_scroll, search_scroll + direction))
								redrawScreen()
							end
						end
						if tab == 3 and in_playlist_result == false and y >= getPlaylistListStartY() then
							local max_scroll = getMaxPlaylistScroll()
							if max_scroll > 0 then
								playlist_scroll = math.max(0, math.min(max_scroll, playlist_scroll + direction))
								redrawScreen()
							end
						end
					end,
				function()
					local event = os.pullEvent("redraw_screen")

					redrawScreen()
				end
			)
		end
	end
end

function audioLoop()
	while true do

		-- AUDIO
		if playing and now_playing then
			local thisnowplayingid = now_playing.id
			if playing_id ~= thisnowplayingid then
				playing_id = thisnowplayingid
				last_download_url = api_base_url .. "?v=" .. version .. "&id=" .. textutils.urlEncode(playing_id)
				playing_status = 0
				needs_next_chunk = 1

				http.request({url = last_download_url, binary = true})
				is_loading = true

				os.queueEvent("redraw_screen")
				os.queueEvent("audio_update")
			elseif playing_status == 1 and needs_next_chunk == 1 then

				while true do
					local chunk = player_handle.read(size)
					if not chunk then
						if looping == 2 or (looping == 1 and #queue == 0) then
							playing_id = nil
							elseif looping == 1 and #queue > 0 then
								table.insert(queue, now_playing)
								now_playing = queue[1]
								table.remove(queue, 1)
								playing_id = nil
						else
							if #queue > 0 then
								now_playing = queue[1]
								table.remove(queue, 1)
								playing_id = nil
							else
								now_playing = nil
								playing = false
								playing_id = nil
								is_loading = false
								is_error = false
							end
						end

						os.queueEvent("redraw_screen")

						player_handle.close()
						needs_next_chunk = 0
						break
					else
						if start then
							chunk, start = start .. chunk, nil
							size = size + 4
						end
				
						buffer = decoder(chunk)
						
						local fn = {}
						for i, speaker in ipairs(speakers) do 
							fn[i] = function()
								local name = peripheral.getName(speaker)
								if #speakers > 1 then
									if speaker.playAudio(buffer, volume) then
										parallel.waitForAny(
											function()
												repeat until select(2, os.pullEvent("speaker_audio_empty")) == name
											end,
											function()
												local event = os.pullEvent("playback_stopped")
												return
											end
										)
										if not playing or playing_id ~= thisnowplayingid then
											return
										end
									end
								else
									while not speaker.playAudio(buffer, volume) do
										parallel.waitForAny(
											function()
												repeat until select(2, os.pullEvent("speaker_audio_empty")) == name
											end,
											function()
												local event = os.pullEvent("playback_stopped")
												return
											end
										)
										if not playing or playing_id ~= thisnowplayingid then
											return
										end
									end
								end
								if not playing or playing_id ~= thisnowplayingid then
									return
								end
							end
						end
						
						local ok, err = pcall(parallel.waitForAll, table.unpack(fn))
						if not ok then
							needs_next_chunk = 2
							is_error = true
							break
						end
						
						-- If we're not playing anymore, exit the chunk processing loop
						if not playing or playing_id ~= thisnowplayingid then
							break
						end
					end
				end
				os.queueEvent("audio_update")
			end
		end

		os.pullEvent("audio_update")
	end
end

function httpLoop()
	while true do
		parallel.waitForAny(
			function()
				local event, url, handle = os.pullEvent("http_success")

				if url == last_search_url then
					local payload = textutils.unserialiseJSON(handle.readAll())
					search_results = normalizeSearchResults(payload)
					search_scroll = 0
					os.queueEvent("redraw_screen")
				end
				if url == last_download_url then
					is_loading = false
					player_handle = handle
					start = handle.read(4)
					size = 16 * 1024 - 4
					playing_status = 1
					os.queueEvent("redraw_screen")
					os.queueEvent("audio_update")
				end
			end,
			function()
				local event, url = os.pullEvent("http_failure")	

				if url == last_search_url then
					search_error = true
					os.queueEvent("redraw_screen")
				end
				if url == last_download_url then
					is_loading = false
					is_error = true
					playing = false
					playing_id = nil
					os.queueEvent("redraw_screen")
					os.queueEvent("audio_update")
				end
			end
		)
	end
end

parallel.waitForAny(uiLoop, audioLoop, httpLoop)
