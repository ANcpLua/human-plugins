require("hs.ipc")

local ghostty = os.getenv("HUMAN_TERMINAL_EXECUTABLE")
  or "/Applications/Ghostty.app/Contents/MacOS/ghostty"
local ghosttyBundle = os.getenv("HUMAN_TERMINAL_BUNDLE")
  or "com.mitchellh.ghostty"
local home = assert(os.getenv("HOME"), "HOME is required")
local command = os.getenv("HUMAN_AGENT_COMMAND")
  or ("exec " .. string.format("%q", home .. "/.local/bin/claude") .. " --ide")
local managed = {}
local tasks = {}

local function terminalWindows()
  local windows = {}
  for _, window in ipairs(hs.window.allWindows()) do
    local application = window:application()
    if application
      and application:bundleID() == ghosttyBundle
      and window:isStandard()
      and window:isVisible()
      and not window:isMinimized()
    then
      windows[#windows + 1] = window
    end
  end
  return windows
end

local function tileManaged()
  local windows = {}
  for _, window in ipairs(terminalWindows()) do
    if window:id() and managed[window:id()] then
      windows[#windows + 1] = window
    end
  end
  table.sort(windows, function(left, right)
    return left:frame().x < right:frame().x
  end)
  if #windows == 0 then
    return 0
  end
  local frame = hs.screen.mainScreen():frame()
  local width = frame.w / #windows
  for index, window in ipairs(windows) do
    window:setFrame({
      x = frame.x + (index - 1) * width,
      y = frame.y,
      w = width,
      h = frame.h,
    }, 0)
  end
  return #windows
end

local function claimNewWindows(before)
  for _, window in ipairs(terminalWindows()) do
    if window:id() and not before[window:id()] then
      managed[window:id()] = true
    end
  end
  tileManaged()
end

local function spawn()
  local before = {}
  for _, window in ipairs(terminalWindows()) do
    if window:id() then
      before[window:id()] = true
    end
  end
  local task
  task = hs.task.new(ghostty, function()
    tasks[task] = nil
  end, nil, { "-e", "/bin/zsh", "-lc", command })
  if not task then
    hs.alert.show("Agent launcher could not create the terminal task")
    return
  end
  tasks[task] = true
  if not task:start() then
    tasks[task] = nil
    hs.alert.show("Agent launcher could not start Ghostty")
    return
  end
  for _, delay in ipairs({ 0.7, 1.4, 2.4, 3.6 }) do
    hs.timer.doAfter(delay, function()
      claimNewWindows(before)
    end)
  end
end

humanAgentLauncher = hs.eventtap.new({
  hs.eventtap.event.types.otherMouseDown,
}, function(event)
  local button = event:getProperty(
    hs.eventtap.event.properties.mouseEventButtonNumber
  )
  if button == 2 and event:getFlags().ctrl then
    hs.timer.doAfter(0, spawn)
    return true
  end
  return false
end)
humanAgentLauncher:start()

hs.hotkey.bind({ "ctrl", "alt", "shift" }, "F12", spawn)

function humanAgentLauncherStatus()
  local count = 0
  for _ in pairs(managed) do
    count = count + 1
  end
  return "terminal windows: "
    .. #terminalWindows()
    .. " | managed: "
    .. count
end
