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
    
    -- Initialize mouse position
    pcall(function()
        local mousePos = UserInputService:GetMouseLocation()
        ImGui.mouse.position = Vector2.new(mousePos.X, mousePos.Y)
        ImGui.mouse.lastPosition = Vector2.new(mousePos.X, mousePos.Y)
    end)
    
    -- Setup input handling with better reliability
    UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            ImGui.mouse.leftPressed = true
            ImGui.mouse.leftDown = true
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            ImGui.mouse.leftReleased = true
            ImGui.mouse.leftDown = false
        end
    end)
    
    -- Update mouse position with better error handling
    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            -- Store last position before updating
            ImGui.mouse.lastPosition = Vector2.new(ImGui.mouse.position.X, ImGui.mouse.position.Y)
            
            -- Use pcall to prevent errors if mouse position is temporarily unavailable
            pcall(function()
                local mousePos = input.Position
                ImGui.mouse.position = Vector2.new(mousePos.X, mousePos.Y)
            end)
        end
    end)
    
    -- Limit render rate for better performance
    local lastFrameTime = tick()
    local frameRateLimit = 1/60  -- Limit to 60 FPS
    
    -- Main render loop with improved performance
    RunService.RenderStepped:Connect(function()
        -- Throttle updates for better performance
        local currentTime = tick()
        local deltaTime = currentTime - lastFrameTime
        
        if deltaTime >= frameRateLimit then
            lastFrameTime = currentTime
            ImGui.NewFrame()
        end
    end)
    
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
        RunService.RenderStepped:Connect(function()
            if ImGui.cursor and ImGui.cursor.Parent then
                pcall(function()
                    ImGui.cursor.Position = UDim2.new(0, ImGui.mouse.position.X, 0, ImGui.mouse.position.Y)
                end)
            end
        end)
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

-- Begin a new frame
function ImGui.NewFrame()
    -- Reset frame state
    ImGui.hoveredItem = nil
    
    -- Reset slider dragging state if mouse released
    if ImGui.mouse.leftReleased and ImGui.activeDragSlider then
        ImGui.activeDragSlider = nil
    end
    
    -- Move clicks from current frame to last frame (make a deep copy)
    ImGui.lastClickedElements = {}
    for id, value in pairs(ImGui.clickedElements) do
        ImGui.lastClickedElements[id] = value
    end
    ImGui.clickedElements = {}
    
    -- Clear flags from previous frame
    ImGui.mouse.leftPressed = false
    ImGui.mouse.leftReleased = false
    
    -- Process window interactions
    for _, window in ipairs(ImGui.windows) do
        if window.instance then
            -- Check if mouse is hovering over window
            local windowPos = window.instance.Position
            local windowSize = window.instance.Size
            local mouseInWindow = ImGui.mouse.position.X >= windowPos.X.Offset and
                                 ImGui.mouse.position.X <= windowPos.X.Offset + windowSize.X.Offset and
                                 ImGui.mouse.position.Y >= windowPos.Y.Offset and
                                 ImGui.mouse.position.Y <= windowPos.Y.Offset + windowSize.Y.Offset
            
            -- Fix dragging logic - more reliable tracking
            if window.dragging and not ImGui.mouse.leftDown then
                window.dragging = false
            elseif window.dragging and ImGui.mouse.leftDown then
                -- Use mouse movement delta for smoother dragging
                local mouseDelta = Vector2.new(
                    ImGui.mouse.position.X - ImGui.mouse.lastPosition.X,
                    ImGui.mouse.position.Y - ImGui.mouse.lastPosition.Y
                )
                
                -- Only move if there's actually movement (prevents jittering)
                if math.abs(mouseDelta.X) > 0 or math.abs(mouseDelta.Y) > 0 then
                    local currentPos = window.instance.Position
                    local newPos = UDim2.new(
                        0, currentPos.X.Offset + mouseDelta.X,
                        0, currentPos.Y.Offset + mouseDelta.Y
                    )
                    window.instance.Position = newPos
                end
            elseif ImGui.mouse.leftPressed and mouseInWindow then
                -- Check if click is in title bar
                local titleBarHeight = 30
                if ImGui.mouse.position.Y < windowPos.Y.Offset + titleBarHeight then
                    window.dragging = true
                    
                    -- Make this window active
                    if ImGui.activeWindow ~= window then
                        ImGui.BringWindowToFront(window)
                    end
                end
            end
        end
    end
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
function ImGui.Begin(title, x, y, width, height)
    -- Generate unique ID for window
    local windowId = title
    
    -- Check if window already exists
    local window = nil
    for i, w in ipairs(ImGui.windows) do
        if w.id == windowId then
            window = w
            break
        end
    end
    
    -- Create new window if needed
    if not window then
        window = {
            id = windowId,
            title = title,
            position = Vector2.new(x or 100, y or 100),
            size = Vector2.new(width or 300, height or 200),
            dragging = false,
            dragOffset = Vector2.new(0, 0),
            contentArea = {
                position = Vector2.new(0, 0),
                size = Vector2.new(0, 0),
                cursor = Vector2.new(0, 0)
            },
            children = {},
            connections = {} -- Store window-specific connections
        }
        
        -- Create window UI with improved styling
        window.instance = createInstance("Frame", {
            Name = "ImGuiWindow_" .. title,
            Position = UDim2.new(0, window.position.X, 0, window.position.Y),
            Size = UDim2.new(0, window.size.X, 0, window.size.Y),
            BackgroundColor3 = ImGui.style.windowBgColor,
            BorderSizePixel = 0, -- No border, we'll use UICorner for rounding
            Parent = ImGui.ScreenGui
        })
        
        -- Add corner rounding
        createInstance("UICorner", {
            CornerRadius = UDim.new(0, ImGui.style.windowRounding),
            Parent = window.instance
        })
        
        -- Add subtle shadow effect if not disabled for performance
        if ImGui.style.useGradients then
            -- Simplified shadow approach - just a stroke
            createInstance("UIStroke", {
                Color = Color3.fromRGB(0, 0, 0),
                Thickness = 2,
                Transparency = 0.7,
                Parent = window.instance
            })
        end
        
        -- Create title bar with gradient
        window.titleBar = createInstance("Frame", {
            Name = "TitleBar",
            Position = UDim2.new(0, 0, 0, 0),
            Size = UDim2.new(1, 0, 0, 30), -- Slightly taller
            BackgroundColor3 = ImGui.style.titleBarColor,
            BorderSizePixel = 0,
            Parent = window.instance
        })
        
        -- Round top corners only
        createInstance("UICorner", {
            CornerRadius = UDim.new(0, ImGui.style.windowRounding),
            Parent = window.titleBar
        })
        
        -- Add gradient to title bar if gradients enabled
        if ImGui.style.useGradients then
            createInstance("UIGradient", {
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0),
                    NumberSequenceKeypoint.new(1, 0.2)
                }),
                Rotation = 90,
                Parent = window.titleBar
            })
        end
        
        -- Create title text with better spacing
        window.titleText = createInstance("TextLabel", {
            Name = "TitleText",
            Position = UDim2.new(0, 10, 0, 0),
            Size = UDim2.new(1, -20, 1, 0),
            BackgroundTransparency = 1,
            Text = title,
            TextColor3 = ImGui.style.titleTextColor,
            TextSize = ImGui.font.size + 2, -- Slightly larger title text
            Font = ImGui.font.bold,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = window.titleBar
        })
        
        -- Create stylish close button
        window.closeButton = createInstance("TextButton", {
            Name = "CloseButton",
            Position = UDim2.new(1, -30, 0, 0),
            Size = UDim2.new(0, 30, 0, 30),
            BackgroundTransparency = 1,
            Text = "✕",
            TextColor3 = ImGui.style.titleTextColor,
            TextSize = ImGui.font.size + 2,
            Font = ImGui.font.bold,
            Parent = window.titleBar
        })
        
        -- Close button hover effect
        ImGui.Connect(window.closeButton, "MouseEnter", function()
            window.closeButton.TextColor3 = Color3.fromRGB(255, 100, 100)
        end)
        
        ImGui.Connect(window.closeButton, "MouseLeave", function()
            window.closeButton.TextColor3 = ImGui.style.titleTextColor
        end)
        
        -- Close button functionality
        ImGui.Connect(window.closeButton, "MouseButton1Click", function()
            ImGui.DestroyWindow(window)
        end)
        
        -- Create content area with improved styling
        window.contentFrame = createInstance("ScrollingFrame", {
            Name = "ContentFrame",
            Position = UDim2.new(0, ImGui.style.windowPadding.X, 0, 30 + ImGui.style.windowPadding.Y),
            Size = UDim2.new(
                1, -ImGui.style.windowPadding.X * 2,
                1, -(30 + ImGui.style.windowPadding.Y * 2)
            ),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = ImGui.style.scrollbarSize,
            ScrollBarImageColor3 = ImGui.style.borderColor,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            Parent = window.instance
        })
        
        -- Initialize content cursor
        window.contentArea.cursor = Vector2.new(0, 0)
        
        -- Add window to list
        table.insert(ImGui.windows, window)
    else
        -- Reset content cursor for existing window
        window.contentArea.cursor = Vector2.new(0, 0)
        
        -- Clear existing content
        for _, child in ipairs(window.contentFrame:GetChildren()) do
            child:Destroy()
        end
    end
    
    -- Make this window the active window
    ImGui.BringWindowToFront(window)
    ImGui.activeWindow = window
    
    return true
end

-- End a window definition
function ImGui.End()
    local window = ImGui.activeWindow
    if window then
        -- Update content canvas size
        window.contentFrame.CanvasSize = UDim2.new(
            0, 0, 
            0, window.contentArea.cursor.Y + ImGui.style.windowPadding.Y
        )
        
        -- Clear active window
        ImGui.activeWindow = nil
    end
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

-- Helper function to add a new item to the current window's content
function ImGui.AddItem(item, width, height)
    local window = ImGui.activeWindow
    if not window then return end
    
    local itemPosition = Vector2.new(
        window.contentArea.cursor.X,
        window.contentArea.cursor.Y
    )
    
    -- Set position and parent
    item.Position = UDim2.new(0, itemPosition.X, 0, itemPosition.Y)
    item.Parent = window.contentFrame
    
    -- Update cursor position for next item
    window.contentArea.cursor = Vector2.new(
        window.contentArea.cursor.X,
        window.contentArea.cursor.Y + height + ImGui.style.itemSpacing.Y
    )
    
    return itemPosition
end

-- Text label
function ImGui.Text(text)
    local window = ImGui.activeWindow
    if not window then return end
    
    -- Create label element
    local textSize = calculateTextSize(text, ImGui.font.size, ImGui.font.regular)
    local label = createInstance("TextLabel", {
        Name = "ImGuiText",
        Size = UDim2.new(0, textSize.X, 0, textSize.Y),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = ImGui.style.textColor,
        TextSize = ImGui.font.size,
        Font = ImGui.font.regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center
    })
    
    ImGui.AddItem(label, textSize.X, textSize.Y)
end

-- Button control
function ImGui.Button(label, width)
    local window = ImGui.activeWindow
    if not window then return false end
    
    -- Generate unique ID for this button
    ImGui.nextItemId = ImGui.nextItemId + 1
    local buttonId = "Button_" .. label .. "_" .. ImGui.nextItemId
    
    -- Check if this button was clicked in the previous frame
    local wasClicked = ImGui.lastClickedElements[buttonId] == true
    if wasClicked then
        -- Remove from last clicked list so it's only processed once
        ImGui.lastClickedElements[buttonId] = nil
    end
    
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
    
    -- Register click handler to store in state for next frame
    ImGui.Connect(button, "MouseButton1Click", function()
        ImGui.clickedElements[buttonId] = true
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
    
    -- Check if this checkbox was clicked in the previous frame
    local wasClicked = ImGui.lastClickedElements[checkboxId] == true
    if wasClicked then
        -- Remove from last clicked list so it's only processed once
        ImGui.lastClickedElements[checkboxId] = nil
        -- Toggle the value
        value = not value
    end
    
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
    
    -- Register click handler
    ImGui.Connect(clickArea, "MouseButton1Click", function()
        ImGui.clickedElements[checkboxId] = true
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
    
    -- Check if this slider is being dragged
    if ImGui.activeDragSlider == sliderId then
        -- Use current mouse position to update slider
        local percent = math.clamp(
            (ImGui.mouse.position.X - track.AbsolutePosition.X) / sliderWidth,
            0, 1
        )
        
        -- Update value based on percentage
        value = min + percent * (max - min)
        
        -- Update fill width and handle position
        fillWidth = percent * sliderWidth
        fill.Size = UDim2.new(0, fillWidth, 1, 0)
        handle.Position = UDim2.new(0, fillWidth - 6, 0, -4)
        
        -- Update value label
        valueLabel.Text = string.format(format, value)
    end
    
    -- Function to update slider value based on mouse position
    local function updateSliderValue(mousePos)
        -- Calculate percentage
        local percent = math.clamp(
            (mousePos.X - track.AbsolutePosition.X) / sliderWidth,
            0, 1
        )
        
        -- Update value
        value = min + percent * (max - min)
        
        -- Update UI
        fillWidth = percent * sliderWidth
        fill.Size = UDim2.new(0, fillWidth, 1, 0)
        handle.Position = UDim2.new(0, fillWidth - 6, 0, -4)
        valueLabel.Text = string.format(format, value)
    end
    
    -- Track click handler (immediate jump to clicked position)
    ImGui.Connect(trackClickArea, "MouseButton1Down", function(x, y)
        ImGui.activeDragSlider = sliderId
        updateSliderValue(Vector2.new(x, y))
        handle.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
    end)
    
    -- Handle drag
    ImGui.Connect(handleButton, "MouseButton1Down", function()
        ImGui.activeDragSlider = sliderId
        handle.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
    end)
    
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
    
    -- Calculate width
    local separatorWidth = window.contentFrame.AbsoluteSize.X - ImGui.style.windowPadding.X * 2
    local separatorHeight = 1
    
    -- Create separator line
    local separator = createInstance("Frame", {
        Name = "ImGuiSeparator",
        Size = UDim2.new(0, separatorWidth, 0, separatorHeight),
        BackgroundColor3 = ImGui.style.borderColor,
        BorderSizePixel = 0
    })
    
    ImGui.AddItem(separator, separatorWidth, separatorHeight)
    ImGui.Spacing(ImGui.style.itemSpacing.Y)
end

-- Group controls with same line
function ImGui.SameLine(offsetX)
    local window = ImGui.activeWindow
    if not window then return end
    
    -- Save Y position and move X position
    local xPos = window.contentArea.cursor.X + (offsetX or ImGui.style.itemSpacing.X)
    window.contentArea.cursor = Vector2.new(xPos, window.contentArea.cursor.Y - ImGui.style.itemSpacing.Y)
end

-- Cleanup all resources and connections when shutting down
function ImGui.Shutdown()
    -- Clean up all connections first
    ImGui.CleanupConnections()
    
    -- Destroy all windows
    for i = #ImGui.windows, 1, -1 do
        ImGui.DestroyWindow(ImGui.windows[i])
    end
    
    -- Clear collections
    ImGui.windows = {}
    ImGui.clickedElements = {}
    ImGui.lastClickedElements = {}
    ImGui.hitTestCache = {}
    
    -- Remove main screen gui
    if ImGui.ScreenGui then
        ImGui.ScreenGui:Destroy()
        ImGui.ScreenGui = nil
    end
    
    -- Remove custom cursor if it exists
    if ImGui.cursor then
        ImGui.cursor:Destroy()
        ImGui.cursor = nil
    end
    
    -- Restore cursor visibility
    pcall(function()
        UserInputService.MouseIconEnabled = true
    end)
    
    -- Reset states
    ImGui.activeWindow = nil
    ImGui.hoveredItem = nil
    ImGui.activeItem = nil
    ImGui.activeDragSlider = nil
    ImGui.nextItemId = 0
end

-- Finalize the ImGui library
ImGui.VERSION = "1.0.5"
ImGui.LAST_UPDATED = "2023-12-20"

-- Return the ImGui library object
return ImGui
