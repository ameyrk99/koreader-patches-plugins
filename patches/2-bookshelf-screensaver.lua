--[[
Koreader Bookshelf Screensaver
Version: 1.0.0
Amey Khairnar
https://github.com/ameyrk99/koreader-patches-plugins
]] --

local Device               = require("device")
local Blitbuffer           = require("ffi/blitbuffer")
local UIManager            = require("ui/uimanager")
local ScreenSaverWidget    = require("ui/widget/screensaverwidget")
local Font                 = require("ui/font")
local TextWidget           = require("ui/widget/textwidget")
local ImageWidget          = require("ui/widget/imagewidget")
local DataStorage          = require("datastorage")
local SQ3                  = require("lua-ljsqlite3/init")
local lfs                  = require("libs/libkoreader-lfs")
local gettext              = require("gettext")
local T                    = require("ffi/util").template

local FrameContainer       = require("ui/widget/container/framecontainer")
local HorizontalGroup      = require("ui/widget/horizontalgroup")
local VerticalGroup        = require("ui/widget/verticalgroup")
local HorizontalSpan       = require("ui/widget/horizontalspan")
local VerticalSpan         = require("ui/widget/verticalspan")
local OverlapGroup         = require("ui/widget/overlapgroup")

local Screen               = Device.screen

local STATISTICS_DB_PATH   = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
local STACK_DECOR_PATH     = DataStorage:getDataDir() .. "/resources/bookshelf-screensaver-decor.png"

local STACK_OFFSET_LEFT    = Screen:scaleBySize(20)
local STACK_OFFSET_BOTTOM  = Screen:scaleBySize(20)
local BOOK_SPACING         = Screen:scaleBySize(3)
local SHADOW_SIZE_RIGHT    = Screen:scaleBySize(5)
local SHADOW_SIZE_BOTTOM   = Screen:scaleBySize(2)
local STACK_DECOR_WIDTH    = Screen:scaleBySize(200)
local STACK_DECOR_HEIGHT   = Screen:scaleBySize(200)
-- Decor is anchored to the top right of top book. Offset exists to accommodate whitespace.
-- Increasing X pushes decor to wards right edge, Increasing Y pushes decor downwards
-- Cat Image https://www.citypng.com/photo/8d974a35/vector-black-cat-silhouette-sitting-hd-transparent-png
local STACK_DECOR_OFFSET_X = Screen:scaleBySize(50)
local STACK_DECOR_OFFSET_Y = Screen:scaleBySize(5)

-- ============================================================================
-- LOCALIZATION
-- ============================================================================

local PATCH_L10N           = {
    en = {
        -- Screensaver text
        ["Unknown"] = "Unknown",
        ["Unknown Author"] = "Unknown Author",
        ["%1 left"] = "%1 left",

        -- Menu text
        ["Bookshelf"] = "Bookshelf",
        ["Bookshelf Settings"] = "Bookshelf Settings",

        -- Sections
        ["── Display ──"] = "── Display ──",
        ["── Books ──"] = "── Books ──",
        ["── Actions ──"] = "── Actions ──",

        -- Display settings
        ["Show background"] = "Show background",
        ["Show stack decoration"] = "Show stack decoration",
        ["Show time left"] = "Show time left",
        ["Show percent completed"] = "Show percent completed",
        ["Show progress bands"] = "Show progress bands",
        ["Use random colors"] = "Use random colors",
        ["Use misaligned stack"] = "Use misaligned stack",

        -- Book settings
        ["Set number of books"] = "Set number of books",
        ["Set 'finished' threshold (%)"] = "Set 'finished' threshold (%)",
        ["Set font size"] = "Set font size",

        -- Actions
        ["Restore defaults"] = "Restore defaults",
        ["Settings restored"] = "Settings restored to defaults",

        -- UI
        ["%1h %2m"] = "%1h %2m",
        ["%1m"] = "%1m",
    },
}

local function l10nLookup(msg)
    local lang = "en"
    if G_reader_settings and G_reader_settings.readSetting then
        lang = G_reader_settings:readSetting("language") or "en"
    end
    local lang_base = lang:match("^([a-z]+)") or lang
    local map = PATCH_L10N[lang] or PATCH_L10N[lang_base] or PATCH_L10N.en or {}
    return map[msg]
end

local function _(msg)
    return l10nLookup(msg) or gettext(msg)
end

-- ============================================================================
-- SETTINGS
-- ============================================================================

local SETTINGS = {
    SHOW_BACKGROUND = "bookshelf_screensaver_show_background",
    SHOW_STACK_DECOR = "bookshelf_screensaver_show_stack_decor",
    SHOW_TIME_LEFT = "bookshelf_screensaver_show_time_left",
    SHOW_PERCENT = "bookshelf_screensaver_show_percent",
    SHOW_BANDS = "bookshelf_screensaver_show_bands",
    USE_RANDOM_COLORS = "bookshelf_screensaver_use_random_colors",
    USE_MISALIGNED_STACK = "bookshelf_screensaver_use_misaligned_stack",
    NUM_BOOKS = "bookshelf_screensaver_num_books",
    FINISHED_THRESHOLD = "bookshelf_screensaver_finished_threshold",
    MIN_BOOK_SIZE = "bookshelf_minimum_pages",
    FONT_SIZE = "bookshelf_screensaver_font_size"
}

local DEFAULTS = {
    SHOW_BACKGROUND = true,
    SHOW_STACK_DECOR = true,
    SHOW_TIME_LEFT = true,
    SHOW_PERCENT = false,
    SHOW_BANDS = true,
    USE_RANDOM_COLORS = false,
    USE_MISALIGNED_STACK = true,
    NUM_BOOKS = 5,
    MIN_BOOK_SIZE = 0,
    FINISHED_THRESHOLD = 97,
    FONT_SIZE = 6,
}

local function getSetting(key, default)
    local val = G_reader_settings:readSetting(key)
    if val ~= nil then
        return val
    end
    return default
end

local function isSettingEnabled(key, default)
    local val = G_reader_settings:readSetting(key)
    if val ~= nil then
        return val
    end
    return default
end

-- ============================================================================
-- DATABASE FUNCTIONS
-- ============================================================================

local function getRecentBooks(max_books, min_book_size)
    if not STATISTICS_DB_PATH or STATISTICS_DB_PATH == "" then
        return nil
    end

    local attrs = lfs.attributes(STATISTICS_DB_PATH, "mode")
    if attrs ~= "file" then
        return nil
    end

    local ok_conn, conn = pcall(SQ3.open, STATISTICS_DB_PATH)
    if not ok_conn or not conn then
        return nil
    end

    local sql_stmt = string.format([[
        SELECT b.title, b.authors, b.pages, MAX(p.start_time) as last_read,
            (SELECT page FROM page_stat WHERE id_book = b.id ORDER BY start_time DESC LIMIT 1) as current_page,
            b.total_read_time, b.total_read_pages
        FROM book b
        LEFT JOIN page_stat p ON b.id = p.id_book
        GROUP BY b.id
        HAVING current_page * 100 >= pages
            AND b.pages >= %d
        ORDER BY last_read DESC
        LIMIT %d;
    ]], min_book_size, max_books)

    local books = {}
    local ok_query, results = pcall(function()
        return conn:exec(sql_stmt)
    end)

    conn:close()

    if not ok_query or not results or not results[1] then
        return nil
    end

    local num_rows = #results[1]

    for i = 1, num_rows do
        local title = results[1][i] or _("Unknown")
        local author = results[2][i] or _("Unknown Author")
        local pages = tonumber(results[3][i]) or 200
        local current_page = tonumber(results[5][i]) or 1
        local total_read_time = tonumber(results[6][i]) or 0
        local total_read_pages = tonumber(results[7][i]) or 0

        local time_remaining = nil
        if total_read_pages > 0 and current_page < pages then
            local avg_time_per_page = total_read_time / total_read_pages
            local pages_remaining = pages - current_page
            time_remaining = math.floor(avg_time_per_page * pages_remaining)
        end

        local progress = math.floor((current_page / pages) * 100)
        if progress > 100 then progress = 100 end
        if progress < 0 then progress = 0 end

        table.insert(books, {
            title = title,
            author = author,
            pages = pages,
            progress = progress,
            time_remaining = time_remaining,
        })
    end

    if #books == 0 then
        return nil
    end

    return books
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function formatTimeRemaining(seconds)
    if not seconds or seconds <= 0 then
        return nil
    end
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if hours > 0 then
        return T(_("%1h %2m"), hours, minutes)
    else
        return T(_("%1m"), minutes)
    end
end

local function createDottedBackground()
    local screen_size = Screen:getSize()
    local bb = Blitbuffer.new(screen_size.w, screen_size.h, Blitbuffer.TYPE_BB8)

    bb:fill(Blitbuffer.Color8(0xF5))

    local dot_spacing = Screen:scaleBySize(25)
    local dot_size = Screen:scaleBySize(3)
    for y = dot_spacing, screen_size.h - 1, dot_spacing do
        for x = dot_spacing, screen_size.w - 1, dot_spacing do
            bb:paintRect(x, y, dot_size, dot_size, Blitbuffer.Color8(0xD0))
        end
    end

    return ImageWidget:new {
        image = bb,
        width = screen_size.w,
        height = screen_size.h,
    }
end

local function isColorScreen()
    return Screen:isColorEnabled() or Screen:isColorScreen()
end

local function getBookColor(index, use_random)
    if isColorScreen() then
        local colors = {
            Blitbuffer.ColorRGB32(120, 190, 120, 255), -- green
            Blitbuffer.ColorRGB32(130, 160, 220, 255), -- blue
            Blitbuffer.ColorRGB32(190, 140, 210, 255), -- purple
            Blitbuffer.ColorRGB32(220, 120, 120, 255), -- red
        }
        if use_random then
            return colors[math.random(1, #colors)]
        else
            return colors[((index - 1) % #colors) + 1]
        end
    else
        local shades = {
            Blitbuffer.Color8(0xB8),
            Blitbuffer.Color8(0x98),
            Blitbuffer.Color8(0xC8),
            Blitbuffer.Color8(0xA8),
            Blitbuffer.Color8(0xB0),
            Blitbuffer.Color8(0xA0),
        }
        if use_random then
            return shades[math.random(1, #shades)]
        else
            return shades[((index - 1) % #shades) + 1]
        end
    end
end

local function getShadowColor()
    if isColorScreen() then
        return Blitbuffer.ColorRGB32(80, 80, 80, 255)
    else
        return Blitbuffer.Color8(0x40)
    end
end

local function getBandColor()
    if isColorScreen() then
        return Blitbuffer.ColorRGB32(230, 190, 50, 255) -- yellow/gold
    else
        return Blitbuffer.Color8(0xF0)
    end
end

local function getAccentColor()
    if isColorScreen() then
        return Blitbuffer.ColorRGB32(240, 235, 220, 255)
    else
        return Blitbuffer.Color8(0xE0)
    end
end

local function considerBookComplete(progress, threshold)
    return progress >= threshold
end

-- ============================================================================
-- MAIN WIDGET BUILDER
-- ============================================================================

local function buildBookshelfWidget()
    local screen_size = Screen:getSize()

    -- Load settings
    local show_background = isSettingEnabled(SETTINGS.SHOW_BACKGROUND, DEFAULTS.SHOW_BACKGROUND)
    local show_stack_decor = isSettingEnabled(SETTINGS.SHOW_STACK_DECOR, DEFAULTS.SHOW_STACK_DECOR)
    local show_time_left = isSettingEnabled(SETTINGS.SHOW_TIME_LEFT, DEFAULTS.SHOW_TIME_LEFT)
    local show_percent_completed = isSettingEnabled(SETTINGS.SHOW_PERCENT, DEFAULTS.SHOW_PERCENT)
    local show_progress_bands = isSettingEnabled(SETTINGS.SHOW_BANDS, DEFAULTS.SHOW_BANDS)
    local use_random_colors = isSettingEnabled(SETTINGS.USE_RANDOM_COLORS, DEFAULTS.USE_RANDOM_COLORS)
    local use_misaligned_stack = isSettingEnabled(SETTINGS.USE_MISALIGNED_STACK, DEFAULTS.USE_MISALIGNED_STACK)
    local num_books = getSetting(SETTINGS.NUM_BOOKS, DEFAULTS.NUM_BOOKS)
    local finished_threshold = getSetting(SETTINGS.FINISHED_THRESHOLD, DEFAULTS.FINISHED_THRESHOLD)
    local font_size = getSetting(SETTINGS.FONT_SIZE, DEFAULTS.FONT_SIZE)
    local min_book_size = getSetting(SETTINGS.MIN_BOOK_SIZE, DEFAULTS.MIN_BOOK_SIZE)

    local books = getRecentBooks(num_books, min_book_size)
    if not books then
        books = {
            { title = "Project Hail Mary",              author = "Andy Weir",           pages = 600,  progress = 67, time_remaining = 12660 },
            { title = "A Psalm for the Wild-Built",     author = "Becky Chambers",      pages = 180,  progress = 5,  time_remaining = 6540 },
            { title = "A Game of Thrones",              author = "George R. R. Martin", pages = 1200, progress = 98, time_remaining = 500 },
            { title = "A Knight of the Seven Kingdoms", author = "George R. R. Martin", pages = 500,  progress = 33, time_remaining = 11370 },
            { title = "Pride and Prejudice",            author = "Jane Austen",         pages = 280,  progress = 0,  time_remaining = 0 },
            { title = "Dracula",                        author = "Bram Stoker",         pages = 1100, progress = 80, time_remaining = 12000 },
        }
    end

    local book_count = #books
    local books_stack = VerticalGroup:new {
        align = "left",
    }

    local top_width = screen_size.w
    local max_width = 0
    local total_height = 0


    local shadow_color = getShadowColor()
    local band_color = getBandColor()

    for i = 1, book_count do
        local book = books[i]
        local left_offset = use_misaligned_stack and Screen:scaleBySize(math.random(0, 20)) or 0

        local page_count = book.pages or 300
        -- Normalize books to range [200, 1000]. 200 are "thin", 1000 are "thick"
        local normalized_page_count = math.min(math.max(page_count, 200), 1000)

        local size_factor = (normalized_page_count - 200) / (1000 - 200)
        -- Book height will be 8-13% of screen size
        local book_height = math.floor(screen_size.h * (0.08 + (size_factor * 0.05)))
        -- Book width will be 60-85% of screen size
        local book_width = math.floor(screen_size.w * (0.6 + (size_factor * 0.25)))

        if i == 1 then
            top_width = book_width
        end
        max_width = math.max(max_width, book_width)
        total_height = total_height + book_height + SHADOW_SIZE_BOTTOM

        local base_color = getBookColor(i, use_random_colors)
        local accent_color = getAccentColor()

        local progress = book.progress or 0
        local progress_width = math.floor(book_width * (progress / 100))

        -- Title is a little bigger and further increase both texts by 1-2 size
        local title_face = Font:getFace("cfont", Screen:scaleBySize((font_size + 2) + math.floor(size_factor * 2)))
        local author_face = Font:getFace("cfont", Screen:scaleBySize(font_size + math.floor(size_factor * 2)))

        local title_widget = TextWidget:new {
            text = book.title,
            face = title_face,
            fgcolor = Blitbuffer.COLOR_BLACK,
            bold = true,
            max_width = 0.8 * book_width,
        }

        local author_text = book.author
        if show_percent_completed and progress > 0 and not considerBookComplete(progress, finished_threshold) then
            author_text = progress .. "% • " .. author_text
        end
        if show_time_left and progress > 0 and not considerBookComplete(progress, finished_threshold) and book.time_remaining then
            author_text = T(_("%1 left"), formatTimeRemaining(book.time_remaining)) .. " • " .. author_text
        end

        local author_widget = TextWidget:new {
            text = author_text,
            face = author_face,
            fgcolor = Blitbuffer.Color8(0x40),
            max_width = 0.7 * book_width,
        }

        local spine = nil
        if considerBookComplete(progress, finished_threshold) then
            spine = HorizontalGroup:new {
                FrameContainer:new {
                    width = book_width,
                    height = book_height,
                    background = base_color,
                    bordersize = 0,
                    padding = 0,
                    HorizontalSpan:new { width = book_width },
                },
            }
        else
            spine = HorizontalGroup:new {
                FrameContainer:new {
                    width = progress_width,
                    height = book_height,
                    background = base_color,
                    bordersize = 0,
                    padding = 0,
                    HorizontalSpan:new { width = progress_width },
                },
                FrameContainer:new {
                    width = book_width - progress_width,
                    height = book_height,
                    background = accent_color,
                    bordersize = 0,
                    padding = 0,
                    HorizontalSpan:new { width = book_width - progress_width },
                }
            }
        end

        spine = FrameContainer:new {
            width = book_width,
            height = book_height,
            bordersize = 1,
            color = Blitbuffer.COLOR_BLACK,
            padding = 0,
            spine,
        }

        -- --------------------------------- Shadows -------------------------------- --
        spine = OverlapGroup:new {
            dimen = { w = book_width + SHADOW_SIZE_RIGHT, h = book_height + SHADOW_SIZE_RIGHT },
            spine,
            HorizontalGroup:new {
                HorizontalSpan:new { width = book_width },
                FrameContainer:new {
                    width = SHADOW_SIZE_RIGHT,
                    height = book_height + SHADOW_SIZE_BOTTOM,
                    background = shadow_color,
                    bordersize = 0,
                    padding = 0,
                    HorizontalSpan:new { width = book_width },
                },
            },
            VerticalGroup:new {
                VerticalSpan:new { width = book_height },
                FrameContainer:new {
                    width = book_width,
                    height = SHADOW_SIZE_BOTTOM,
                    background = shadow_color,
                    bordersize = 0,
                    padding = 0,
                    HorizontalSpan:new { width = book_height },
                },
            },
        }

        -- ----------------------------- Progress bands ----------------------------- --
        if show_progress_bands then
            -- Different percentage of the book width
            local band_size = math.floor(book_width * 0.02)
            local band_spacing = math.floor(book_width * 0.03)
            local left_band_loc = math.floor(book_width * 0.04)

            if progress >= 25 then
                spine = OverlapGroup:new {
                    dimen = { w = book_width, h = book_height },
                    spine,
                    HorizontalGroup:new {
                        HorizontalSpan:new { width = left_band_loc },
                        FrameContainer:new {
                            width = band_size,
                            height = book_height + 2,
                            background = band_color,
                            bordersize = 1,
                            color = Blitbuffer.COLOR_BLACK,
                            padding = 0,
                            HorizontalSpan:new { width = book_width },
                        },
                    }
                }
            end

            if progress >= 50 then
                spine = OverlapGroup:new {
                    dimen = { w = book_width, h = book_height },
                    spine,
                    HorizontalGroup:new {
                        HorizontalSpan:new { width = left_band_loc + band_spacing },
                        FrameContainer:new {
                            width = band_size,
                            height = book_height + 2,
                            background = band_color,
                            bordersize = 1,
                            color = Blitbuffer.COLOR_BLACK,
                            padding = 0,
                            HorizontalSpan:new { width = book_width },
                        },
                    }
                }
            end

            if progress >= 75 then
                spine = OverlapGroup:new {
                    dimen = { w = book_width, h = book_height },
                    spine,
                    HorizontalGroup:new {
                        HorizontalSpan:new { width = book_width - left_band_loc - band_size },
                        FrameContainer:new {
                            width = band_size,
                            height = book_height + 2,
                            background = band_color,
                            bordersize = 1,
                            color = Blitbuffer.COLOR_BLACK,
                            padding = 0,
                            HorizontalSpan:new { width = book_width },
                        },
                    }
                }
            end

            if considerBookComplete(progress, finished_threshold) then
                spine = OverlapGroup:new {
                    dimen = { w = book_width, h = book_height },
                    spine,
                    HorizontalGroup:new {
                        HorizontalSpan:new { width = book_width - left_band_loc - band_spacing - band_size },
                        FrameContainer:new {
                            width = band_size,
                            height = book_height + 2,
                            background = band_color,
                            bordersize = 1,
                            color = Blitbuffer.COLOR_BLACK,
                            padding = 0,
                            HorizontalSpan:new { width = book_width },
                        },
                    }
                }
            end
        end

        local book_spine = OverlapGroup:new {
            dimen = { w = max_width, h = book_height },
            spine,
            HorizontalGroup:new {
                align = "center",
                HorizontalSpan:new { width = (book_width / 2) - (math.max(title_widget:getSize().w, author_widget:getSize().w) / 2) },
                VerticalGroup:new {
                    align = "center",
                    VerticalSpan:new { width = (book_height - title_widget:getSize().h - author_widget:getSize().h) / 2 },
                    title_widget,
                    VerticalSpan:new { width = -Screen:scaleBySize(2) },
                    author_widget
                }
            }
        }

        table.insert(books_stack, HorizontalGroup:new {
            HorizontalSpan:new { width = left_offset },
            book_spine,
        })

        if i < book_count then
            table.insert(books_stack, VerticalSpan:new { width = BOOK_SPACING })
            total_height = total_height + BOOK_SPACING
        end
    end

    local top_margin = math.max(0, screen_size.h - total_height)

    local main_stack = VerticalGroup:new {
        VerticalSpan:new {
            width = top_margin - STACK_OFFSET_BOTTOM,
        },
        HorizontalGroup:new {
            HorizontalSpan:new { width = STACK_OFFSET_LEFT },
            books_stack
        },
    }

    local final_widget = OverlapGroup:new {
        dimen = screen_size,
    }

    if show_background then
        local bg_widget = createDottedBackground()
        table.insert(final_widget, bg_widget)
    end

    table.insert(final_widget, main_stack)

    -- ------------------------------- Stack decor ------------------------------ --
    local stack_decor_widget = nil
    local stack_decor_attrs = lfs.attributes(STACK_DECOR_PATH, "mode")
    if stack_decor_attrs == "file" then
        stack_decor_widget = ImageWidget:new {
            file = STACK_DECOR_PATH,
            width = STACK_DECOR_WIDTH,
            height = STACK_DECOR_HEIGHT,
            alpha = true,
        }
    end

    if show_stack_decor and stack_decor_widget then
        table.insert(final_widget, VerticalGroup:new {
            VerticalSpan:new {
                width = top_margin - STACK_DECOR_HEIGHT + STACK_DECOR_OFFSET_Y,
            },
            HorizontalGroup:new {
                HorizontalSpan:new { width = top_width - STACK_DECOR_WIDTH + STACK_DECOR_OFFSET_X },
                stack_decor_widget,
            },
        })
    end

    return final_widget
end

-- ============================================================================
-- SCREENSAVER HOOK
-- ============================================================================

local Screensaver = require("ui/screensaver")
local orig_screensaver_show = Screensaver.show

Screensaver.show = function(self)
    if self.screensaver_type ~= "bookshelf" then
        return orig_screensaver_show(self)
    end

    if self.screensaver_widget then
        UIManager:close(self.screensaver_widget)
        self.screensaver_widget = nil
    end

    Device.screen_saver_mode = true

    local widget = buildBookshelfWidget()

    self.screensaver_widget = ScreenSaverWidget:new {
        widget = widget,
        background = Blitbuffer.COLOR_WHITE,
        covers_fullscreen = true,
    }
    self.screensaver_widget.modal = true
    self.screensaver_widget.dithered = true

    UIManager:show(self.screensaver_widget, "full")
end

-- ============================================================================
-- MENU INTEGRATION
-- ============================================================================

local function createSpinnerMenuItem(text, setting_key, default_val, min_val, max_val, step)
    return {
        text = _(text),
        callback = function()
            local SpinWidget = require("ui/widget/spinwidget")
            local current = getSetting(setting_key, default_val)
            local spinner = SpinWidget:new {
                value = current,
                value_min = min_val,
                value_max = max_val,
                value_step = step,
                value_hold_step = step * 5,
                ok_text = _("Save"),
                title_text = _(text),
                callback = function(spin)
                    G_reader_settings:saveSetting(setting_key, spin.value)
                end,
            }
            UIManager:show(spinner)
        end,
        keep_menu_open = true,
    }
end

local orig_dofile = dofile
_G.dofile = function(filepath)
    local result = orig_dofile(filepath)
    if filepath and filepath:match("screensaver_menu%.lua$") then
        if result and result[1] and result[1].sub_item_table then
            local wallpaper_submenu = result[1].sub_item_table

            -- Add screensaver option
            table.insert(wallpaper_submenu, {
                text = _("Bookshelf"),
                checked_func = function()
                    return G_reader_settings:readSetting("screensaver_type") == "bookshelf"
                end,
                callback = function()
                    G_reader_settings:saveSetting("screensaver_type", "bookshelf")
                end,
                radio = true,
            })

            -- Add settings submenu
            table.insert(wallpaper_submenu, {
                text = _("Bookshelf Settings"),
                sub_item_table = {
                    -- Display section
                    {
                        text = _("── Display ──"),
                        enabled = false,
                    },
                    {
                        text = _("Show background"),
                        checked_func = function()
                            return isSettingEnabled(SETTINGS.SHOW_BACKGROUND, DEFAULTS.SHOW_BACKGROUND)
                        end,
                        callback = function()
                            local current = isSettingEnabled(SETTINGS.SHOW_BACKGROUND, DEFAULTS.SHOW_BACKGROUND)
                            G_reader_settings:saveSetting(SETTINGS.SHOW_BACKGROUND, not current)
                        end,
                    },
                    {
                        text = _("Show stack decoration"),
                        checked_func = function()
                            return isSettingEnabled(SETTINGS.SHOW_STACK_DECOR, DEFAULTS.SHOW_STACK_DECOR)
                        end,
                        callback = function()
                            local current = isSettingEnabled(SETTINGS.SHOW_STACK_DECOR, DEFAULTS.SHOW_STACK_DECOR)
                            G_reader_settings:saveSetting(SETTINGS.SHOW_STACK_DECOR, not current)
                        end,
                    },
                    {
                        text = _("Show time left"),
                        checked_func = function()
                            return isSettingEnabled(SETTINGS.SHOW_TIME_LEFT, DEFAULTS.SHOW_TIME_LEFT)
                        end,
                        callback = function()
                            local current = isSettingEnabled(SETTINGS.SHOW_TIME_LEFT, DEFAULTS.SHOW_TIME_LEFT)
                            G_reader_settings:saveSetting(SETTINGS.SHOW_TIME_LEFT, not current)
                        end,
                    },
                    {
                        text = _("Show percent completed"),
                        checked_func = function()
                            return isSettingEnabled(SETTINGS.SHOW_PERCENT, DEFAULTS.SHOW_PERCENT)
                        end,
                        callback = function()
                            local current = isSettingEnabled(SETTINGS.SHOW_PERCENT, DEFAULTS.SHOW_PERCENT)
                            G_reader_settings:saveSetting(SETTINGS.SHOW_PERCENT, not current)
                        end,
                    },
                    {
                        text = _("Show progress bands"),
                        checked_func = function()
                            return isSettingEnabled(SETTINGS.SHOW_BANDS, DEFAULTS.SHOW_BANDS)
                        end,
                        callback = function()
                            local current = isSettingEnabled(SETTINGS.SHOW_BANDS, DEFAULTS.SHOW_BANDS)
                            G_reader_settings:saveSetting(SETTINGS.SHOW_BANDS, not current)
                        end,
                    },
                    {
                        text = _("Use random colors"),
                        checked_func = function()
                            return isSettingEnabled(SETTINGS.USE_RANDOM_COLORS, DEFAULTS.USE_RANDOM_COLORS)
                        end,
                        callback = function()
                            local current = isSettingEnabled(SETTINGS.USE_RANDOM_COLORS, DEFAULTS.USE_RANDOM_COLORS)
                            G_reader_settings:saveSetting(SETTINGS.USE_RANDOM_COLORS, not current)
                        end,
                    },
                    {
                        text = _("Use misaligned stack"),
                        checked_func = function()
                            return isSettingEnabled(SETTINGS.USE_MISALIGNED_STACK, DEFAULTS.USE_MISALIGNED_STACK)
                        end,
                        callback = function()
                            local current = isSettingEnabled(SETTINGS.USE_MISALIGNED_STACK, DEFAULTS
                                .USE_MISALIGNED_STACK)
                            G_reader_settings:saveSetting(SETTINGS.USE_MISALIGNED_STACK, not current)
                        end,
                    },

                    -- Books section
                    {
                        text = _("── Books ──"),
                        enabled = false,
                    },
                    createSpinnerMenuItem("Set number of books", SETTINGS.NUM_BOOKS, DEFAULTS.NUM_BOOKS, 1, 10, 1),
                    createSpinnerMenuItem("Set 'finished' threshold (%)", SETTINGS.FINISHED_THRESHOLD,
                        DEFAULTS.FINISHED_THRESHOLD, 90, 100, 1),
                    createSpinnerMenuItem("Set minimum number of pages of included books", SETTINGS.MIN_BOOK_SIZE, DEFAULTS.MIN_BOOK_SIZE, 0, 999999, 5),
                    createSpinnerMenuItem("Set font size", SETTINGS.FONT_SIZE,
                        DEFAULTS.FONT_SIZE, 4, 10, 1),
                    -- Actions section
                    {
                        text = _("── Actions ──"),
                        enabled = false,
                    },
                    {
                        text = _("Restore defaults"),
                        callback = function()
                            G_reader_settings:delSetting(SETTINGS.SHOW_BACKGROUND)
                            G_reader_settings:delSetting(SETTINGS.SHOW_STACK_DECOR)
                            G_reader_settings:delSetting(SETTINGS.SHOW_TIME_LEFT)
                            G_reader_settings:delSetting(SETTINGS.SHOW_PERCENT)
                            G_reader_settings:delSetting(SETTINGS.SHOW_BANDS)
                            G_reader_settings:delSetting(SETTINGS.USE_RANDOM_COLORS)
                            G_reader_settings:delSetting(SETTINGS.USE_MISALIGNED_STACK)
                            G_reader_settings:delSetting(SETTINGS.NUM_BOOKS)
                            G_reader_settings:delSetting(SETTINGS.FINISHED_THRESHOLD)
                            G_reader_settings:delSetting(SETTINGS.FONT_SIZE)

                            local Notification = require("ui/widget/notification")
                            UIManager:show(Notification:new {
                                text = _("Settings restored"),
                            })
                        end,
                    },
                },
            })
        end
    end
    return result
end
