# Koreader patches & plugins

### [2-bookshelf-screensaver.lua](./patches/2-bookshelf-screensaver.lua)

| Grayscale (Kindle Oasis)                                       | Color (Emulator - Kindle Paperwhite)             |
| -------------------------------------------------------------- | ------------------------------------------------ |
| ![](./imgs/bookshelf_screensaver_grayscale_kindle_oasis.jpeg)  | ![](./imgs/bookshelf_screensaver_color_emu.png)  |
| ![](./imgs/bookshelf_screensaver_grayscale_kindle_oasis1.jpeg) | ![](./imgs/bookshelf_screensaver_color_emu1.png) |

Features:

1. Shows last few recently read books starting from the top.
2. Vertical book stack where the book spines double as progress bars. These scale with page count.
3. Shows time left and/or percent progress (automatically hidden for finished books).
4. Progress bands at 25%, 50%, 75%, and completion milestones.
5. Book cover or custom images as shelf background.
6. Currently open book's cover displayed standing on top of the stack.
7. Decoration on top of the stack.

Config:

| Configurable           | Default          | Note                                                                                                                                                                              |
| ---------------------- | ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Background type        | `Dotted pattern` | Background for bookshelf. Options: `No background`, `Dotted pattern`, `Book cover`, and `Custom image`; Custom image chooses a random image from `koreader/resources/backgrounds` |
| Progression type       | `Progress bar`   | Progression on book spine. Options are `Progress bar`, `Top to bottom` like a book, and `Bottom to top` like filling a glass (also like a book for some languages!)               |
| Show standing book     | `enabled`        | Show the currently reading book stand on top of the stack. **Only shown if a book is open**                                                                                       |
| Show stack decoration  | `disabled`       | Image on top of the stack (provided cat image); Ignored if standing book in use                                                                                                   |
| Show time left in book | `enabled`        | Time left in book. Hidden for finished books                                                                                                                                      |
| Show percent completed | `disabled`       | Progress percentage in the book. Hidden for finished books                                                                                                                        |
| Show progress bands    | `enabled`        | Bands at progress `25%`, `50%`, `75%`, and `finished`                                                                                                                             |
| Randomize book colors  | `disabled`       | Randomize book colors instead of cycling                                                                                                                                          |
| Misaligned stack       | `enabled`        | Slightly offset books for a natural look                                                                                                                                          |
| Number of books        | `5`              | Books to display (might show less if standing book enabled)                                                                                                                       |
| `finished` threshold   | `97`             | Consider book finished if above this % (in order to ignore glossary, appendix, etc pages)                                                                                         |
| Min page threshold     | `0`              | Hide books if below threshold (to filter small PDFs etc)                                                                                                                          |
| Font size              | `6`              | Font size for text. Truncated if too long                                                                                                                                         |

Add your own backgrounds to `koreader/resources/backgrounds` or change the value of `CUSTOM_BG_PATH` if you use another folder.
Websites like https://www.ebookscreensaver.com/ can help you crop image for your device.

Add more or customize book colors in `getBookColor` function.

If you decide to use your own decor (`bookshelf-screensaver-decor.png`) update `STACK_DECOR_OFFSET_X` and `STACK_DECOR_OFFSET_Y` accordingly.

## Installation

1. Copy `2-bookshelf-screensaver.lua` to `koreader/patches`
2. Copy custom images to `koreader/resources/backgrounds` (See [sample](./resources/backgrounds/wave.jpeg))
3. Copy [decoration image](./resources/bookshelf-screensaver-decor.png) to `koreader/resources/bookshelf-screensaver-decor.png`
4. Select "Bookshelf" in `Screen -> Sleep screen -> Wallpaper -> Bookshelf`
5. Configure in `Screen -> Sleep screen -> Wallpaper -> Bookshelf Settings`

## Troubleshooting

- **Standing book not appearing?** Only works when a book is currently open
- **Standing book incorrect/repeated** Statistics take a moment to update. Not noticeable unless you switch books within seconds and sleep.
- **Custom backgrounds not loading?** Ensure images are `.png`, `.jpg`, or `.jpeg` in `koreader/resources/backgrounds/`. Also avoid large images (keep < 1M if possible).
