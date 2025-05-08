-- RobloxImGui: Compact ImGui-style UI library
local ImGui = {
    _VERSION = "1.0.5",
    _AUTHOR = "Claude",
    
    -- State variables
    windows = {},
    activeWindow = nil,
    hoveredItem = nil,
    activeItem = nil,
    
    -- Style configuration - modern dark theme
    style = {
        windowBgColor = Color3.fromRGB(32, 32, 36),
        windowBorderColor = Color3.fromRGB(60, 60, 70),
        titleBarColor = Color3.fromRGB(46, 46, 58),
        titleTextColor = Color3.fromRGB(230, 230, 250),
        buttonColor = Color3.fromRGB(55, 55, 70),
        buttonHoverColor = Color3.fromRGB(75, 75, 100),
        buttonActiveColor = Color3.fromRGB(95, 95, 130),
        textColor = Color3.fromRGB(230, 230, 250),
        borderColor = Color3.fromRGB(70, 70, 85),
        sliderColor = Color3.fromRGB(110, 90, 230),
        checkboxColor = Color3.fromRGB(110, 90, 230),
        inputBgColor = Color3.fromRGB(40, 40, 50),
        framePadding = Vector2.new(8, 6),
        windowPadding = Vector2.new(10, 10),
        itemSpacing = Vector2.new(10, 6),
        scrollbarSize = 10,
        windowRounding = 4,
        frameRounding = 4,
        
        -- Performance options
        useGradients = false,  -- Default to disabled for better performance
        useAnimations = false, -- Default to disabled for better performance
        animationSpeed = 0.05, -- Faster animations (was 0.1)
        minAnimationDistance = 2, -- Don't animate tiny movements
    },
    
    -- UI element IDs
    nextItemId = 0,
    
    -- Font settings (fixed to use Enum.Font instead of Font.new)
    font = {
        regular = Enum.Font.Ubuntu,
        bold = Enum.Font.SourceSansBold,
        size = 14
    },
    
    -- Input tracking
    mouse = {
        position = Vector2.new(0, 0),
        lastPosition = Vector2.new(0, 0),  -- Track last position for better drag detection
        leftPressed = false,
        leftReleased = false,
        leftDown = false
    },
    
    -- Cache for hit testing (optimization)
    hitTestCache = {},
    
    -- Click tracking
    clickedElements = {},     -- Store elements that were clicked
    lastClickedElements = {}, -- Store elements clicked in the previous frame
    
    -- Event connections storage (for cleanup)
    connections = {},
    
    -- Slider dragging state
    activeDragSlider = nil
}

-- Services
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local CoreGui = game:GetService("CoreGui")

-- Constants
local DOUBLE_CLICK_TIME = 0.3
local LOCAL_PLAYER = Players.LocalPlayer

-- Utility functions
local function createInstance(className, properties)
    local instance = Instance.new(className)
    
    for property, value in pairs(properties) do
        instance[property] = value
    end
    
    return instance
end

local function isPointInRect(point, rect)
    return point.X >= rect.Min.X and point.X <= rect.Max.X and
           point.Y >= rect.Min.Y and point.Y <= rect.Max.Y
end

local function calculateTextSize(text, fontSize, font)
    return TextService:GetTextSize(text, fontSize, font, Vector2.new(10000, 10000))
end

-- Initialize the ImGui system
function ImGui.Init(options)
    options = options or {}
    
    -- Create parent ScreenGui with proper error handling
    local success, screenGui
    
    -- Try to place in CoreGui first (works in exploits), but fallback to PlayerGui
    success, screenGui = pcall(function()
        local gui = createInstance("ScreenGui", {
            Name = "ImGuiScreenGui",
            ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling, -- Changed from Global for better performance
            DisplayOrder = 999,
            IgnoreGuiInset = true,
            Parent = CoreGui
        })
        return gui
    end)
    
    -- If failed, try PlayerGui instead
    if not success then
        local playerGui = LOCAL_PLAYER:FindFirstChild("PlayerGui")
        if playerGui then
            screenGui = createInstance("ScreenGui", {
                Name = "ImGuiScreenGui",
                ResetOnSpawn = false,
                ZIndexBehavior = Enum.ZIndexBehavior.Sibling, -- Changed from Global for better performance
                DisplayOrder = 999,
                IgnoreGuiInset = true,
                Parent = playerGui
            })
        else
            -- Last resort: parent to game.Workspace
            screenGui = createInstance("ScreenGui", {
                Name = "ImGuiScreenGui",
                ResetOnSpawn = false,
                ZIndexBehavior = Enum.ZIndexBehavior.Sibling, -- Changed from Global for better performance
                DisplayOrder = 999,
                IgnoreGuiInset = true
            })
            screenGui.Parent = game.Workspace
        end
    end
    
    ImGui.ScreenGui = screenGui
    
    -- Удаляем все старые соединения, если были
    ImGui.Shutdown()
    
    -- Clear all state
    ImGui.windows = {}
    ImGui.activeWindow = nil
    ImGui.hoveredItem = nil
    ImGui.activeItem = nil
    ImGui.clickedElements = {}
    ImGui.lastClickedElements = {}
    ImGui.connections = {}
    ImGui.activeDragSlider = nil
    
    -- Initialize mouse position
    local mousePos = UserInputService:GetMouseLocation()
    ImGui.mouse = {
        position = Vector2.new(mousePos.X, mousePos.Y),
        lastPosition = Vector2.new(mousePos.X, mousePos.Y),
        leftPressed = false,
        leftReleased = false,
        leftDown = false
    }
    
    -- Setup input handling
    local inputBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            ImGui.mouse.leftPressed = true
            ImGui.mouse.leftDown = true
        end
    end)
    table.insert(ImGui.connections, inputBeganConnection)
    
    local inputEndedConnection = UserInputService.InputEnded:Connect(function(input, gameProcessed)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            ImGui.mouse.leftReleased = true
            ImGui.mouse.leftDown = false
            
            -- Сбрасываем активный слайдер при отпускании мыши
            if ImGui.activeDragSlider then
                ImGui.activeDragSlider = nil
            end
        end
    end)
    table.insert(ImGui.connections, inputEndedConnection)
    
    local inputChangedConnection = UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            ImGui.mouse.lastPosition = Vector2.new(ImGui.mouse.position.X, ImGui.mouse.position.Y)
            pcall(function()
                local mousePos = input.Position
                ImGui.mouse.position = Vector2.new(mousePos.X, mousePos.Y)
            end)
        end
    end)
    table.insert(ImGui.connections, inputChangedConnection)
    
    -- Render loop
    local renderStepConnection = RunService.RenderStepped:Connect(function()
        ImGui.NewFrame()
    end)
    table.insert(ImGui.connections, renderStepConnection)
    
    -- Custom cursor is now optional (default: false)
    ImGui.useCustomCursor = options.useCustomCursor or false
    
    if ImGui.useCustomCursor then
        -- Hide default cursor
        UserInputService.MouseIconEnabled = false
        
        -- Create custom cursor
        ImGui.cursor = createInstance("ImageLabel", {
            Name = "ImGuiCursor",
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 24, 0, 24),
            Image = "rbxassetid://6302464334",
            ZIndex = 9999,
            Parent = ImGui.ScreenGui
        })
        
        -- Update cursor position
        local cursorUpdateConnection = RunService.RenderStepped:Connect(function()
            if ImGui.cursor and ImGui.cursor.Parent then
                pcall(function()
                    ImGui.cursor.Position = UDim2.new(0, ImGui.mouse.position.X, 0, ImGui.mouse.position.Y)
                end)
            end
        end)
        table.insert(ImGui.connections, cursorUpdateConnection)
    else
        -- Ensure system cursor is enabled if not using custom
        UserInputService.MouseIconEnabled = true
    end
    
    return ImGui
end

-- Utility function to safely connect events and store connections for cleanup
function ImGui.Connect(instance, event, callback)
    if not instance or not event then return end
    
    -- Create the connection
    local connection = instance[event]:Connect(callback)
    
    -- Store it for later cleanup
    table.insert(ImGui.connections, connection)
    
    return connection
end

-- Cleanup connections to prevent memory leaks
function ImGui.CleanupConnections()
    for i, connection in ipairs(ImGui.connections) do
        if connection.Connected then
            connection:Disconnect()
        end
    end
    ImGui.connections = {}
end

-- Reset state for new frame
function ImGui.NewFrame()
    if not ImGui.ScreenGui then return end
    
    -- Clear any previous state
    ImGui.activeWindow = nil
    ImGui.hoveredItem = nil
    ImGui.nextItemId = 0
    
    -- Check that screenGui still exists (prevent errors)
    if not ImGui.ScreenGui or not ImGui.ScreenGui.Parent then
        return
    end
    
    -- Clear previous windows
    for name, window in pairs(ImGui.windows) do
        if window.frame and window.frame.Parent then
            window.frame.Parent = nil
        end
    end
    ImGui.windows = {}
    
    -- Update input state directly using UserInputService
    ImGui.mouse.leftPressed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and not ImGui.mouse.leftDown
    ImGui.mouse.leftDown = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    
    -- Get current mouse position directly, more reliable
    local mousePos = UserInputService:GetMouseLocation()
    ImGui.mouse.lastPosition = ImGui.mouse.position
    ImGui.mouse.position = Vector2.new(mousePos.X, mousePos.Y)
    
    -- Better click state transfer - make a proper copy
    ImGui.lastClickedElements = {}
    for id, value in pairs(ImGui.clickedElements) do
        ImGui.lastClickedElements[id] = value
    end
    
    -- Reset click state for this new frame
    ImGui.clickedElements = {}
end

-- Clean up window specific connections to prevent memory leaks
function ImGui.CleanWindowConnections(window)
    if not window or not window.connections then return end
    
    for _, connection in ipairs(window.connections) do
        if connection.Connected then
            connection:Disconnect()
        end
    end
    window.connections = {}
end

-- Close and destroy window
function ImGui.DestroyWindow(window)
    if not window then return end
    
    -- Clean up connections
    ImGui.CleanWindowConnections(window)
    
    -- Destroy the window instance
    if window.instance then
        window.instance:Destroy()
        window.instance = nil
    end
    
    -- Remove window from windows list
    for i, w in ipairs(ImGui.windows) do
        if w.id == window.id then
            table.remove(ImGui.windows, i)
            break
        end
    end
end

-- Begin a window
function ImGui.Begin(title, x, y, width, height, flags)
    -- Generate unique ID for this window
    local windowId = "Window_" .. title
    
    -- Create the window object if it doesn't exist
    if not ImGui.windows[windowId] then
        ImGui.windows[windowId] = {
            title = title,
            position = Vector2.new(x or 100, y or 100),
            size = Vector2.new(width or 300, height or 200),
            contentSize = Vector2.new(0, 0),
            isMoving = false,
            moveOffset = Vector2.new(0, 0),
            items = {},
            cursorPos = Vector2.new(ImGui.style.windowPadding.X, ImGui.style.windowPadding.Y + 30), -- Start below title bar
            lastItem = nil,
            sameLine = false,
            layer = 0,
            connections = {} -- Store window-specific connections
        }
    end
    
    local window = ImGui.windows[windowId]
    
    -- Set this as the active window for adding widgets
    ImGui.activeWindow = window
    
    -- Create window frame
    local frame = createInstance("Frame", {
        Name = "ImGuiWindow_" .. title,
        Position = UDim2.new(0, window.position.X, 0, window.position.Y),
        Size = UDim2.new(0, window.size.X, 0, window.size.Y),
        BackgroundColor3 = ImGui.style.windowBgColor,
        BorderSizePixel = 0,
        Parent = ImGui.ScreenGui
    })
    
    -- Add rounded corners
    createInstance("UICorner", {
        CornerRadius = UDim.new(0, ImGui.style.windowRounding),
        Parent = frame
    })
    
    -- Add border
    createInstance("UIStroke", {
        Color = ImGui.style.windowBorderColor,
        Thickness = 1,
        Parent = frame
    })
    
    -- Add title bar
    local titleBar = createInstance("Frame", {
        Name = "TitleBar",
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = ImGui.style.titleBarColor,
        BorderSizePixel = 0,
        Parent = frame
    })
    
    -- Add rounded corners to title bar (top only)
    createInstance("UICorner", {
        CornerRadius = UDim.new(0, ImGui.style.windowRounding),
        Parent = titleBar
    })
    
    -- Create a clip that makes sure only the top corners are rounded
    local titleBarClip = createInstance("Frame", {
        Name = "TitleBarBottomClip",
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0.5, 1),
        BackgroundColor3 = ImGui.style.titleBarColor,
        BorderSizePixel = 0,
        Parent = titleBar
    })
    
    -- Add title text
    local titleText = createInstance("TextLabel", {
        Name = "TitleText",
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.new(1, -50, 1, 0),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = ImGui.style.titleTextColor,
        TextSize = ImGui.font.size,
        Font = ImGui.font.bold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar
    })
    
    -- Add close button
    local closeButton = createInstance("TextButton", {
        Name = "CloseButton",
        Position = UDim2.new(1, -30, 0.5, -10),
        Size = UDim2.new(0, 20, 0, 20),
        BackgroundColor3 = Color3.fromRGB(220, 80, 80),
        Text = "",
        AutoButtonColor = true,
        Parent = titleBar
    })
    
    -- Add rounded corners to close button
    createInstance("UICorner", {
        CornerRadius = UDim.new(0, 4),
        Parent = closeButton
    })
    
    -- Add X symbol to close button
    local closeX = createInstance("TextLabel", {
        Name = "CloseX",
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "×",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 18,
        Font = ImGui.font.bold,
        Parent = closeButton
    })
    
    -- Make the window draggable
    local dragging = false
    local dragInput
    local dragStart
    local startPos
    
    -- Get all mouse input through absolute coordinates
    ImGui.Connect(titleBar, "InputBegan", function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    
    ImGui.Connect(UserInputService, "InputChanged", function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    
    ImGui.Connect(UserInputService, "InputEnded", function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    ImGui.Connect(frame, "InputChanged", function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
            window.position = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)
        end
    end)
    
    -- Handle close button
    ImGui.Connect(closeButton, "MouseButton1Click", function()
        frame.Parent = nil
        ImGui.CleanWindowConnections(windowId)
        ImGui.windows[windowId] = nil
    end)
    
    -- Create content container with clipping
    local contentContainer = createInstance("ScrollingFrame", {
        Name = "ContentContainer",
        Position = UDim2.new(0, 0, 0, 30),
        Size = UDim2.new(1, 0, 1, -30),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = ImGui.style.scrollbarSize,
        ScrollBarImageColor3 = ImGui.style.borderColor,
        CanvasSize = UDim2.new(0, 0, 0, 0), -- Will be updated as content is added
        Parent = frame
    })
    
    -- Set padding
    local contentPadding = createInstance("UIPadding", {
        PaddingLeft = UDim.new(0, ImGui.style.windowPadding.X),
        PaddingRight = UDim.new(0, ImGui.style.windowPadding.X),
        PaddingTop = UDim.new(0, ImGui.style.windowPadding.Y),
        PaddingBottom = UDim.new(0, ImGui.style.windowPadding.Y),
        Parent = contentContainer
    })
    
    -- Store references to UI elements
    window.frame = frame
    window.contentContainer = contentContainer
    
    -- Reset cursor position for new content
    window.cursorPos = Vector2.new(ImGui.style.windowPadding.X, ImGui.style.windowPadding.Y)
    window.sameLine = false
    window.items = {}
    
    -- Return the window object
    return window
end

-- End the current window
function ImGui.End()
    local window = ImGui.activeWindow
    if not window then return end
    
    -- Reset active window
    ImGui.activeWindow = nil
    
    return window
end

-- Bring a window to the front
function ImGui.BringWindowToFront(window)
    -- Find the highest ZIndex among all windows
    local highestZIndex = 0
    for _, w in ipairs(ImGui.windows) do
        if w.instance and w.instance.ZIndex > highestZIndex then
            highestZIndex = w.instance.ZIndex
        end
    end
    
    -- Set this window's ZIndex higher
    window.instance.ZIndex = highestZIndex + 10  -- Use bigger increment to avoid z-fighting
    
    -- List of classes that support ZIndex property
    local zIndexSupportedClasses = {
        ["Frame"] = true,
        ["ImageLabel"] = true,
        ["ImageButton"] = true,
        ["TextLabel"] = true,
        ["TextButton"] = true,
        ["TextBox"] = true,
        ["ScrollingFrame"] = true,
        ["CanvasGroup"] = true,
        ["ViewportFrame"] = true,
    }
    
    -- Adjust child elements' ZIndex properly
    local baseZIndex = window.instance.ZIndex
    for _, child in ipairs(window.instance:GetDescendants()) do
        if zIndexSupportedClasses[child.ClassName] then
            -- Set relative z-index to parent
            child.ZIndex = baseZIndex + (child.ZIndex - 1)
        end
    end
end

-- Add an item to the window
function ImGui.AddItem(instance, width, height)
    local window = ImGui.activeWindow
    if not window then return end
    
    -- Calculate item position based on cursor
    local position
    
    -- If we're on the same line, use the lastItem position to place this item
    if window.sameLine and window.lastItem then
        -- Place at lastItem's position + its width + spacing
        local lastItemWidth = window.lastItem.width or 0
        position = Vector2.new(
            window.lastItem.position.X + lastItemWidth + ImGui.style.itemSpacing.X,
            window.lastItem.position.Y
        )
        
        -- Reset sameLine flag
        window.sameLine = false
    else
        -- Normal positioning using cursor
        position = Vector2.new(window.cursorPos.X, window.cursorPos.Y)
        
        -- Update cursor for next item (move down)
        window.cursorPos = Vector2.new(
            ImGui.style.windowPadding.X,
            window.cursorPos.Y + height + ImGui.style.itemSpacing.Y
        )
    end
    
    -- Set the position of the instance
    instance.Position = UDim2.new(0, position.X, 0, position.Y)
    
    -- Add to window's content container
    instance.Parent = window.contentContainer
    
    -- Update canvas size if needed
    local bottomY = position.Y + height + ImGui.style.windowPadding.Y
    if bottomY > window.contentContainer.CanvasSize.Y.Offset then
        window.contentContainer.CanvasSize = UDim2.new(0, 0, 0, bottomY)
    end
    
    -- Store this item
    local item = {
        instance = instance,
        position = position,
        width = width,
        height = height
    }
    
    -- Save as lastItem for possible SameLine usage
    window.lastItem = item
    
    -- Add to items list
    table.insert(window.items, item)
    
    return position
end

-- Text label
function ImGui.Text(text)
    local window = ImGui.activeWindow
    if not window then return end
    
    -- Calculate text size
    local textSize = calculateTextSize(text, ImGui.font.size, ImGui.font.regular)
    
    -- Create text label
    local textLabel = createInstance("TextLabel", {
        Name = "Text",
        Size = UDim2.new(0, textSize.X, 0, textSize.Y),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = ImGui.style.textColor,
        TextSize = ImGui.font.size,
        Font = ImGui.font.regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center
    })
    
    ImGui.AddItem(textLabel, textSize.X, textSize.Y)
end

-- Button control
function ImGui.Button(label, width)
    local window = ImGui.activeWindow
    if not window then return false end
    
    -- Generate unique ID for this button
    ImGui.nextItemId = ImGui.nextItemId + 1
    local buttonId = "Button_" .. label .. "_" .. ImGui.nextItemId
    
    -- Calculate size
    local textSize = calculateTextSize(label, ImGui.font.size, ImGui.font.regular)
    local buttonWidth = width or textSize.X + ImGui.style.framePadding.X * 2
    local buttonHeight = textSize.Y + ImGui.style.framePadding.Y * 2
    
    -- Create button container for animations
    local container = createInstance("Frame", {
        Name = "ButtonContainer_" .. label,
        Size = UDim2.new(0, buttonWidth, 0, buttonHeight),
        BackgroundTransparency = 1
    })
    
    -- Create button element with improved styling
    local button = createInstance("TextButton", {
        Name = "ImGuiButton_" .. label,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = ImGui.style.buttonColor,
        BorderSizePixel = 0,
        Text = label,
        TextColor3 = ImGui.style.textColor,
        TextSize = ImGui.font.size,
        Font = ImGui.font.regular,
        AutoButtonColor = true, -- Use Roblox's built-in hover effects
        Parent = container
    })
    
    -- Add rounded corners
    createInstance("UICorner", {
        CornerRadius = UDim.new(0, ImGui.style.frameRounding),
        Parent = button
    })
    
    -- Add subtle stroke
    createInstance("UIStroke", {
        Color = ImGui.style.borderColor,
        Thickness = 1,
        Transparency = 0.5,
        Parent = button
    })
    
    -- Add the button to the window
    local position = ImGui.AddItem(container, buttonWidth, buttonHeight)
    
    -- Use direct click detection instead of frame-to-frame state
    local wasClicked = false
    
    -- Register direct click handler
    ImGui.Connect(button, "MouseButton1Click", function()
        wasClicked = true
    end)
    
    return wasClicked
end

-- Checkbox control
function ImGui.Checkbox(label, value)
    local window = ImGui.activeWindow
    if not window then return value end
    
    -- Generate unique ID for this checkbox
    ImGui.nextItemId = ImGui.nextItemId + 1
    local checkboxId = "Checkbox_" .. label .. "_" .. ImGui.nextItemId
    
    -- Track if checkbox was clicked in this frame
    local wasClicked = false
    
    -- Calculate sizes
    local textSize = calculateTextSize(label, ImGui.font.size, ImGui.font.regular)
    local checkboxSize = 16
    local totalWidth = checkboxSize + 8 + textSize.X
    local totalHeight = math.max(checkboxSize, textSize.Y)
    
    -- Create checkbox container
    local container = createInstance("Frame", {
        Name = "ImGuiCheckbox_" .. label,
        Size = UDim2.new(0, totalWidth, 0, totalHeight),
        BackgroundTransparency = 1
    })
    
    -- Create clickable area (invisible button)
    local clickArea = createInstance("TextButton", {
        Name = "CheckboxClickArea",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        Parent = container
    })
    
    -- Create checkbox box with modern style
    local box = createInstance("Frame", {
        Name = "CheckboxBox",
        Position = UDim2.new(0, 0, 0, (totalHeight - checkboxSize) / 2),
        Size = UDim2.new(0, checkboxSize, 0, checkboxSize),
        BackgroundColor3 = value and ImGui.style.checkboxColor or ImGui.style.buttonColor,
        BorderSizePixel = 0,
        Parent = container
    })
    
    -- Add rounded corners
    createInstance("UICorner", {
        CornerRadius = UDim.new(0, 4),
        Parent = box
    })
    
    -- Add subtle stroke
    createInstance("UIStroke", {
        Color = ImGui.style.borderColor,
        Thickness = 1,
        Transparency = 0.5,
        Parent = box
    })
    
    -- Create checkmark if checked
    if value then
        -- Use a checkmark icon
        local checkmark = createInstance("ImageLabel", {
            Name = "Checkmark",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 12, 0, 12),
            BackgroundTransparency = 1,
            Image = "rbxassetid://6031094667", -- Checkmark icon
            ImageColor3 = Color3.fromRGB(255, 255, 255),
            Parent = box
        })
    end
    
    -- Create label text
    local labelText = createInstance("TextLabel", {
        Name = "CheckboxLabel",
        Position = UDim2.new(0, checkboxSize + 8, 0, 0),
        Size = UDim2.new(0, textSize.X, 0, totalHeight),
        BackgroundTransparency = 1,
        Text = label,
        TextColor3 = ImGui.style.textColor,
        TextSize = ImGui.font.size,
        Font = ImGui.font.regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Parent = container
    })
    
    local position = ImGui.AddItem(container, totalWidth, totalHeight)
    
    -- Register direct click handler that toggles the value immediately
    ImGui.Connect(clickArea, "MouseButton1Click", function()
        value = not value
        wasClicked = true
        
        -- Update visual immediately
        box.BackgroundColor3 = value and ImGui.style.checkboxColor or ImGui.style.buttonColor
        
        -- Update checkmark
        box:ClearAllChildren()
        
        -- Re-add corners
        createInstance("UICorner", {
            CornerRadius = UDim.new(0, 4),
            Parent = box
        })
        
        -- Re-add stroke
        createInstance("UIStroke", {
            Color = ImGui.style.borderColor,
            Thickness = 1,
            Transparency = 0.5,
            Parent = box
        })
        
        if value then
            local checkmark = createInstance("ImageLabel", {
                Name = "Checkmark",
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.5, 0),
                Size = UDim2.new(0, 12, 0, 12),
                BackgroundTransparency = 1,
                Image = "rbxassetid://6031094667", -- Checkmark icon
                ImageColor3 = Color3.fromRGB(255, 255, 255),
                Parent = box
            })
        end
    end)
    
    -- Hover effects
    ImGui.Connect(clickArea, "MouseEnter", function()
        if box and box.Parent then
            box.BackgroundColor3 = value and ImGui.style.checkboxColor or ImGui.style.buttonHoverColor
        end
    end)
    
    ImGui.Connect(clickArea, "MouseLeave", function()
        if box and box.Parent then
            box.BackgroundColor3 = value and ImGui.style.checkboxColor or ImGui.style.buttonColor
        end
    end)
    
    return value
end

-- Slider control
function ImGui.Slider(label, value, min, max, format)
    local window = ImGui.activeWindow
    if not window then return value end
    
    format = format or "%.1f"
    
    -- Generate unique ID for this slider
    ImGui.nextItemId = ImGui.nextItemId + 1
    local sliderId = "Slider_" .. label .. "_" .. ImGui.nextItemId
    
    -- Ensure value is within limits
    value = math.max(min, math.min(max, value))
    
    -- Calculate sizes
    local textSize = calculateTextSize(label, ImGui.font.size, ImGui.font.regular)
    local valueText = string.format(format, value)
    local valueTextSize = calculateTextSize(valueText, ImGui.font.size, ImGui.font.regular)
    
    local sliderWidth = 150
    local sliderHeight = 12 -- Thinner, more modern look
    
    local totalWidth = math.max(textSize.X + 8 + sliderWidth + 8 + valueTextSize.X, 200)
    local totalHeight = math.max(textSize.Y, 20, valueTextSize.Y) -- Add minimum height for better touch
    
    -- Create slider container
    local container = createInstance("Frame", {
        Name = "ImGuiSlider_" .. label,
        Size = UDim2.new(0, totalWidth, 0, totalHeight),
        BackgroundTransparency = 1
    })
    
    -- Create label text
    local labelText = createInstance("TextLabel", {
        Name = "SliderLabel",
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(0, textSize.X, 0, totalHeight),
        BackgroundTransparency = 1,
        Text = label,
        TextColor3 = ImGui.style.textColor,
        TextSize = ImGui.font.size,
        Font = ImGui.font.regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Parent = container
    })
    
    -- Create slider track with improved styling
    local track = createInstance("Frame", {
        Name = "SliderTrack",
        Position = UDim2.new(0, textSize.X + 8, 0, (totalHeight - sliderHeight) / 2),
        Size = UDim2.new(0, sliderWidth, 0, sliderHeight),
        BackgroundColor3 = ImGui.style.buttonColor,
        BorderSizePixel = 0,
        Parent = container
    })
    
    -- Clickable area covering track for better input handling
    local trackClickArea = createInstance("TextButton", {
        Name = "TrackClickArea",
        Size = UDim2.new(1, 0, 0, 24), -- Larger clickable area
        Position = UDim2.new(0, 0, 0.5, -12),
        BackgroundTransparency = 1,
        Text = "",
        Parent = track
    })
    
    -- Add rounded corners to track
    createInstance("UICorner", {
        CornerRadius = UDim.new(1, 0), -- Fully rounded
        Parent = track
    })
    
    -- Calculate fill width based on current value
    local fillWidth = (value - min) / (max - min) * sliderWidth
    
    -- Create slider fill with improved styling
    local fill = createInstance("Frame", {
        Name = "SliderFill",
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(0, fillWidth, 1, 0),
        BackgroundColor3 = ImGui.style.sliderColor,
        BorderSizePixel = 0,
        Parent = track
    })
    
    -- Add rounded corners to fill
    createInstance("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = fill
    })
    
    -- Create slider handle
    local handle = createInstance("Frame", {
        Name = "SliderHandle",
        Position = UDim2.new(0, fillWidth - 6, 0, -4),
        Size = UDim2.new(0, 12, 0, 20),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = track
    })
    
    -- Make handle draggable with TextButton
    local handleButton = createInstance("TextButton", {
        Name = "HandleButton",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        Parent = handle
    })
    
    -- Add rounded corners to handle
    createInstance("UICorner", {
        CornerRadius = UDim.new(0.5, 0),
        Parent = handle
    })
    
    -- Add shadow to handle
    createInstance("UIStroke", {
        Color = ImGui.style.borderColor,
        Thickness = 1,
        Transparency = 0.5,
        Parent = handle
    })
    
    -- Create value text
    local valueLabel = createInstance("TextLabel", {
        Name = "SliderValue",
        Position = UDim2.new(0, textSize.X + 8 + sliderWidth + 8, 0, 0),
        Size = UDim2.new(0, valueTextSize.X, 0, totalHeight),
        BackgroundTransparency = 1,
        Text = valueText,
        TextColor3 = ImGui.style.textColor,
        TextSize = ImGui.font.size,
        Font = ImGui.font.regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Parent = container
    })
    
    local position = ImGui.AddItem(container, totalWidth, totalHeight)
    
    -- Variable to track if slider is currently being dragged in this frame
    local isDraggingInThisFrame = false
    
    -- Function to update slider value based on mouse position
    local function updateSliderValue(mousePos)
        -- Calculate percentage
        local percent = math.clamp(
            (mousePos.X - track.AbsolutePosition.X) / track.AbsoluteSize.X,
            0, 1
        )
        
        -- Update value
        value = min + percent * (max - min)
        
        -- Update UI
        local newFillWidth = percent * sliderWidth
        fill.Size = UDim2.new(0, newFillWidth, 1, 0)
        handle.Position = UDim2.new(0, newFillWidth - 6, 0, -4)
        valueLabel.Text = string.format(format, value)
    end
    
    -- Track click handler (immediate jump to clicked position)
    ImGui.Connect(trackClickArea, "MouseButton1Down", function(x, y)
        ImGui.activeDragSlider = sliderId
        isDraggingInThisFrame = true
        updateSliderValue(Vector2.new(x, y))
        handle.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
    end)
    
    -- Handle drag start
    ImGui.Connect(handleButton, "MouseButton1Down", function()
        ImGui.activeDragSlider = sliderId
        isDraggingInThisFrame = true
        handle.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
    end)
    
    -- Update on mouse move if we're dragging this slider
    if ImGui.activeDragSlider == sliderId and ImGui.mouse.leftDown then
        updateSliderValue(ImGui.mouse.position)
    end
    
    -- Handle hover effect
    ImGui.Connect(handleButton, "MouseEnter", function()
        if handle and handle.Parent then
            handle.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
        end
    end)
    
    ImGui.Connect(handleButton, "MouseLeave", function()
        if handle and handle.Parent and ImGui.activeDragSlider ~= sliderId then
            handle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        end
    end)
    
    return value
end

-- Input text control
function ImGui.InputText(label, text, width)
    local window = ImGui.activeWindow
    if not window then return text end
    
    -- Generate unique ID for this input
    ImGui.nextItemId = ImGui.nextItemId + 1
    local inputId = "Input_" .. label .. "_" .. ImGui.nextItemId
    
    -- Calculate sizes
    local labelSize = calculateTextSize(label, ImGui.font.size, ImGui.font.regular)
    local inputWidth = width or 150
    local inputHeight = ImGui.font.size + ImGui.style.framePadding.Y * 2
    
    local totalWidth = labelSize.X + 8 + inputWidth
    local totalHeight = math.max(labelSize.Y, inputHeight)
    
    -- Create input container
    local container = createInstance("Frame", {
        Name = "ImGuiInput_" .. label,
        Size = UDim2.new(0, totalWidth, 0, totalHeight),
        BackgroundTransparency = 1
    })
    
    -- Create label text
    local labelText = createInstance("TextLabel", {
        Name = "InputLabel",
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(0, labelSize.X, 0, totalHeight),
        BackgroundTransparency = 1,
        Text = label,
        TextColor3 = ImGui.style.textColor,
        TextSize = ImGui.font.size,
        Font = ImGui.font.regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Parent = container
    })
    
    -- Create input box container for styling
    local inputContainer = createInstance("Frame", {
        Name = "InputContainer",
        Position = UDim2.new(0, labelSize.X + 8, 0, (totalHeight - inputHeight) / 2),
        Size = UDim2.new(0, inputWidth, 0, inputHeight),
        BackgroundColor3 = ImGui.style.inputBgColor,
        BorderSizePixel = 0,
        Parent = container
    })
    
    -- Add rounded corners
    createInstance("UICorner", {
        CornerRadius = UDim.new(0, ImGui.style.frameRounding),
        Parent = inputContainer
    })
    
    -- Add subtle stroke
    createInstance("UIStroke", {
        Color = ImGui.style.borderColor,
        Thickness = 1,
        Transparency = 0.5,
        Parent = inputContainer
    })
    
    -- Create input box with better performance settings
    local inputBox = createInstance("TextBox", {
        Name = "InputBox",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(1, -10, 1, -2), -- Add padding inside
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = ImGui.style.textColor,
        TextSize = ImGui.font.size,
        Font = ImGui.font.regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        PlaceholderText = "Enter text...",
        PlaceholderColor3 = Color3.fromRGB(150, 150, 150),
        Parent = inputContainer
    })
    
    local position = ImGui.AddItem(container, totalWidth, totalHeight)
    
    -- Simpler hover and focus handling for better performance
    local hoverColor = Color3.fromRGB(
        math.min(255, ImGui.style.inputBgColor.R * 255 + 10),
        math.min(255, ImGui.style.inputBgColor.G * 255 + 10),
        math.min(255, ImGui.style.inputBgColor.B * 255 + 10)
    )
    
    local focusColor = Color3.fromRGB(
        math.min(255, ImGui.style.inputBgColor.R * 255 + 15),
        math.min(255, ImGui.style.inputBgColor.G * 255 + 15),
        math.min(255, ImGui.style.inputBgColor.B * 255 + 20)
    )
    
    -- Direct event handling instead of tween animations for better performance
    ImGui.Connect(inputBox, "MouseEnter", function()
        if inputContainer and inputContainer.Parent then
            inputContainer.BackgroundColor3 = hoverColor
        end
    end)
    
    ImGui.Connect(inputBox, "MouseLeave", function()
        if not inputContainer or not inputContainer.Parent then return end
        if not inputBox:IsFocused() then
            inputContainer.BackgroundColor3 = ImGui.style.inputBgColor
        end
    end)
    
    -- Focus effect
    ImGui.Connect(inputBox, "Focused", function()
        if not inputContainer or not inputContainer.Parent then return end
        inputContainer.BackgroundColor3 = focusColor
        
        -- Highlight the stroke directly
        local stroke = inputContainer:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = ImGui.style.sliderColor
            stroke.Transparency = 0
        end
    end)
    
    -- Capture text changes and reset appearance
    local newText = text
    ImGui.Connect(inputBox, "FocusLost", function()
        if not inputContainer or not inputContainer.Parent then return end
        newText = inputBox.Text
        
        inputContainer.BackgroundColor3 = ImGui.style.inputBgColor
        
        -- Reset the stroke directly
        local stroke = inputContainer:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = ImGui.style.borderColor
            stroke.Transparency = 0.5
        end
    end)
    
    return newText
end

-- Add spacing between controls
function ImGui.Spacing(height)
    local window = ImGui.activeWindow
    if not window then return end
    
    height = height or ImGui.style.itemSpacing.Y * 2
    
    -- Update cursor position
    window.contentArea.cursor = Vector2.new(
        window.contentArea.cursor.X,
        window.contentArea.cursor.Y + height
    )
end

-- Add a separator line
function ImGui.Separator()
    local window = ImGui.activeWindow
    if not window then return end
    
    local width = window.size.X - ImGui.style.windowPadding.X * 2
    local height = 1
    
    local separator = createInstance("Frame", {
        Name = "Separator",
        Size = UDim2.new(0, width, 0, height),
        BackgroundColor3 = ImGui.style.borderColor,
        BorderSizePixel = 0,
        BackgroundTransparency = 0.7
    })
    
    ImGui.AddItem(separator, width, height + ImGui.style.itemSpacing.Y)
end

-- Group controls with same line
function ImGui.SameLine(offsetX)
    local window = ImGui.activeWindow
    if not window then return end
    
    -- Save Y position and move X position
    local xPos = window.contentArea.cursor.X + (offsetX or ImGui.style.itemSpacing.X)
    window.contentArea.cursor = Vector2.new(xPos, window.contentArea.cursor.Y - ImGui.style.itemSpacing.Y)
end

-- Shutdown function - очищает все соединения и ресурсы
function ImGui.Shutdown()
    -- Отключаем все соединения
    for _, connection in ipairs(ImGui.connections or {}) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    ImGui.connections = {}
    
    -- Очищаем окна
    for _, window in pairs(ImGui.windows or {}) do
        if window.frame and window.frame.Parent then
            window.frame.Parent = nil
        end
    end
    ImGui.windows = {}
    
    -- Удаляем ScreenGui, если он существует
    if ImGui.ScreenGui and ImGui.ScreenGui.Parent then
        ImGui.ScreenGui:Destroy()
        ImGui.ScreenGui = nil
    end
    
    -- Сбрасываем состояние мыши
    if ImGui.mouse then
        ImGui.mouse.leftDown = false
        ImGui.mouse.leftPressed = false
        ImGui.mouse.leftReleased = false
    end
    
    -- Сбрасываем активный слайдер
    ImGui.activeDragSlider = nil
    
    -- Включаем стандартный курсор
    UserInputService.MouseIconEnabled = true
end

-- Finalize the ImGui library
ImGui.VERSION = "1.0.5"
ImGui.LAST_UPDATED = "2023-12-20"

-- Return the ImGui library object
return ImGui
