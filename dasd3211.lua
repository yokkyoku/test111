-- RobloxImGui: Compact ImGui-style UI library
local ImGui = {
    _VERSION = "1.0.0",
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
        leftPressed = false,
        leftReleased = false,
        leftDown = false
    }
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
function ImGui.Init()
    -- Create parent ScreenGui
    ImGui.ScreenGui = createInstance("ScreenGui", {
        Name = "ImGuiScreenGui",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Global,
        DisplayOrder = 999,
        IgnoreGuiInset = true,
        Parent = CoreGui
    })
    
    -- Setup input handling
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
    
    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            ImGui.mouse.position = Vector2.new(input.Position.X, input.Position.Y)
        end
    end)
    
    -- Main render loop
    RunService.RenderStepped:Connect(function()
        ImGui.NewFrame()
    end)
    
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
        ImGui.cursor.Position = UDim2.new(0, ImGui.mouse.position.X, 0, ImGui.mouse.position.Y)
    end)
    
    return ImGui
end

-- Begin a new frame
function ImGui.NewFrame()
    -- Reset frame state
    ImGui.hoveredItem = nil
    
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
            
            -- Check if title bar is being dragged
            if window.dragging and not ImGui.mouse.leftDown then
                window.dragging = false
            elseif window.dragging then
                local newPos = UDim2.new(
                    0, ImGui.mouse.position.X - window.dragOffset.X,
                    0, ImGui.mouse.position.Y - window.dragOffset.Y
                )
                window.instance.Position = newPos
            elseif ImGui.mouse.leftPressed and mouseInWindow then
                -- Check if click is in title bar
                local titleBarHeight = 28
                if ImGui.mouse.position.Y < windowPos.Y.Offset + titleBarHeight then
                    window.dragging = true
                    window.dragOffset = Vector2.new(
                        ImGui.mouse.position.X - windowPos.X.Offset,
                        ImGui.mouse.position.Y - windowPos.Y.Offset
                    )
                    
                    -- Make this window active
                    if ImGui.activeWindow ~= window then
                        ImGui.BringWindowToFront(window)
                    end
                end
            end
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
            children = {}
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
        
        -- Add subtle shadow effect
        local shadow = createInstance("ImageLabel", {
            Name = "Shadow",
            Size = UDim2.new(1, 20, 1, 20),
            Position = UDim2.new(0, -10, 0, -10),
            BackgroundTransparency = 1,
            Image = "rbxassetid://5554236805",
            ImageColor3 = Color3.fromRGB(0, 0, 0),
            ImageTransparency = 0.65,
            ScaleType = Enum.ScaleType.Slice,
            SliceCenter = Rect.new(23, 23, 277, 277),
            ZIndex = -1,
            Parent = window.instance
        })
        
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
        
        -- Add gradient to title bar
        createInstance("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 0.2)
            }),
            Rotation = 90,
            Parent = window.titleBar
        })
        
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
        window.closeButton.MouseEnter:Connect(function()
            window.closeButton.TextColor3 = Color3.fromRGB(255, 100, 100)
        end)
        
        window.closeButton.MouseLeave:Connect(function()
            window.closeButton.TextColor3 = ImGui.style.titleTextColor
        end)
        
        -- Close button functionality
        window.closeButton.MouseButton1Click:Connect(function()
            window.instance:Destroy()
            window.instance = nil
            
            -- Remove window from windows list
            for i, w in ipairs(ImGui.windows) do
                if w.id == window.id then
                    table.remove(ImGui.windows, i)
                    break
                end
            end
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
    window.instance.ZIndex = highestZIndex + 1
    
    -- Adjust child elements' ZIndex
    for _, child in ipairs(window.instance:GetDescendants()) do
        child.ZIndex = child.ZIndex + highestZIndex
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
        BorderSizePixel = 0, -- No border, using UICorner instead
        Text = label,
        TextColor3 = ImGui.style.textColor,
        TextSize = ImGui.font.size,
        Font = ImGui.font.regular,
        Parent = container
    })
    
    -- Add rounded corners
    createInstance("UICorner", {
        CornerRadius = UDim.new(0, ImGui.style.frameRounding),
        Parent = button
    })
    
    -- Add subtle gradient
    createInstance("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 0.1)
        }),
        Rotation = 90,
        Parent = button
    })
    
    -- Add subtle stroke
    createInstance("UIStroke", {
        Color = ImGui.style.borderColor,
        Thickness = 1,
        Transparency = 0.5,
        Parent = button
    })
    
    local position = ImGui.AddItem(container, buttonWidth, buttonHeight)
    
    -- Check for interactions
    local isHovered = ImGui.mouse.position.X >= button.AbsolutePosition.X and
                     ImGui.mouse.position.X <= button.AbsolutePosition.X + buttonWidth and
                     ImGui.mouse.position.Y >= button.AbsolutePosition.Y and
                     ImGui.mouse.position.Y <= button.AbsolutePosition.Y + buttonHeight
    
    if isHovered then
        ImGui.hoveredItem = buttonId
        button.BackgroundColor3 = ImGui.style.buttonHoverColor
        
        -- Add hover animation
        TweenService:Create(button, TweenInfo.new(0.2), {
            BackgroundColor3 = ImGui.style.buttonHoverColor
        }):Play()
    else
        -- Reset color if not hovered
        TweenService:Create(button, TweenInfo.new(0.2), {
            BackgroundColor3 = ImGui.style.buttonColor
        }):Play()
    end
    
    local isClicked = isHovered and ImGui.mouse.leftPressed
    if isClicked then
        ImGui.activeItem = buttonId
        
        -- Add click animation
        TweenService:Create(button, TweenInfo.new(0.1), {
            BackgroundColor3 = ImGui.style.buttonActiveColor,
            Size = UDim2.new(0.98, 0, 0.98, 0),
            Position = UDim2.new(0.01, 0, 0.01, 0)
        }):Play()
        
        -- Reset after animation
        task.delay(0.1, function()
            TweenService:Create(button, TweenInfo.new(0.1), {
                Size = UDim2.new(1, 0, 1, 0),
                Position = UDim2.new(0, 0, 0, 0)
            }):Play()
        end)
    end
    
    return isClicked
end

-- Checkbox control
function ImGui.Checkbox(label, value)
    local window = ImGui.activeWindow
    if not window then return value end
    
    -- Generate unique ID for this checkbox
    ImGui.nextItemId = ImGui.nextItemId + 1
    local checkboxId = "Checkbox_" .. label .. "_" .. ImGui.nextItemId
    
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
    
    -- Add gradient
    createInstance("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 0.1)
        }),
        Rotation = 90,
        Parent = box
    })
    
    -- Add subtle stroke
    createInstance("UIStroke", {
        Color = ImGui.style.borderColor,
        Thickness = 1,
        Transparency = 0.5,
        Parent = box
    })
    
    -- Create checkmark if checked with nicer animation
    if value then
        -- Use a nicer checkmark icon
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
        
        -- Add appear animation
        checkmark.Size = UDim2.new(0, 0, 0, 0)
        TweenService:Create(checkmark, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 12, 0, 12)
        }):Play()
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
    
    -- Check for interactions
    local isHovered = ImGui.mouse.position.X >= container.AbsolutePosition.X and
                     ImGui.mouse.position.X <= container.AbsolutePosition.X + totalWidth and
                     ImGui.mouse.position.Y >= container.AbsolutePosition.Y and
                     ImGui.mouse.position.Y <= container.AbsolutePosition.Y + totalHeight
    
    if isHovered then
        ImGui.hoveredItem = checkboxId
        -- Animate hover effect
        TweenService:Create(box, TweenInfo.new(0.1), {
            BackgroundColor3 = value and ImGui.style.checkboxColor or ImGui.style.buttonHoverColor
        }):Play()
    else
        -- Reset color
        TweenService:Create(box, TweenInfo.new(0.1), {
            BackgroundColor3 = value and ImGui.style.checkboxColor or ImGui.style.buttonColor
        }):Play()
    end
    
    local isClicked = isHovered and ImGui.mouse.leftPressed
    if isClicked then
        ImGui.activeItem = checkboxId
        value = not value
        
        -- Animate click
        TweenService:Create(box, TweenInfo.new(0.1), {
            BackgroundColor3 = value and ImGui.style.checkboxColor or ImGui.style.buttonColor,
            Size = UDim2.new(0, checkboxSize * 0.8, 0, checkboxSize * 0.8)
        }):Play()
        
        task.delay(0.1, function()
            TweenService:Create(box, TweenInfo.new(0.1), {
                Size = UDim2.new(0, checkboxSize, 0, checkboxSize)
            }):Play()
        end)
        
        -- Update checkmark with animation
        if value then
            local checkmark = createInstance("ImageLabel", {
                Name = "Checkmark",
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.5, 0),
                Size = UDim2.new(0, 0, 0, 0),
                BackgroundTransparency = 1,
                Image = "rbxassetid://6031094667", -- Checkmark icon
                ImageColor3 = Color3.fromRGB(255, 255, 255),
                Parent = box
            })
            
            TweenService:Create(checkmark, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Size = UDim2.new(0, 12, 0, 12)
            }):Play()
        else
            for _, child in ipairs(box:GetChildren()) do
                if child.Name == "Checkmark" then
                    -- Fade out animation
                    TweenService:Create(child, TweenInfo.new(0.1), {
                        Size = UDim2.new(0, 0, 0, 0),
                        ImageTransparency = 1
                    }):Play()
                    
                    task.delay(0.1, function()
                        child:Destroy()
                    end)
                end
            end
        end
    end
    
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
    
    -- Add rounded corners to track
    createInstance("UICorner", {
        CornerRadius = UDim.new(1, 0), -- Fully rounded
        Parent = track
    })
    
    -- Create slider fill with improved styling
    local fillWidth = (value - min) / (max - min) * sliderWidth
    local fill = createInstance("Frame", {
        Name = "SliderFill",
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(0, fillWidth, 1, 0),
        BackgroundColor3 = ImGui.style.sliderColor,
        BorderSizePixel = 0,
        Parent = track
    })
    
    -- Add rounded corners to fill and gradient
    createInstance("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = fill
    })
    
    -- Add gradient to fill
    createInstance("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 0.2)
        }),
        Rotation = 90,
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
    
    -- Check for interactions
    local isTrackHovered = ImGui.mouse.position.X >= track.AbsolutePosition.X and
                          ImGui.mouse.position.X <= track.AbsolutePosition.X + sliderWidth and
                          ImGui.mouse.position.Y >= track.AbsolutePosition.Y - 5 and
                          ImGui.mouse.position.Y <= track.AbsolutePosition.Y + sliderHeight + 5
    
    if isTrackHovered then
        ImGui.hoveredItem = sliderId
        handle.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
    else
        handle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    end
    
    local isActive = ImGui.activeItem == sliderId
    if isTrackHovered and ImGui.mouse.leftPressed then
        ImGui.activeItem = sliderId
        isActive = true
        
        -- Add click animation
        TweenService:Create(handle, TweenInfo.new(0.1), {
            Size = UDim2.new(0, 14, 0, 22),
            Position = UDim2.new(0, fillWidth - 7, 0, -5)
        }):Play()
    end
    
    if isActive and (ImGui.mouse.leftDown or ImGui.mouse.leftPressed) then
        -- Calculate new value based on mouse position
        local percent = math.clamp(
            (ImGui.mouse.position.X - track.AbsolutePosition.X) / sliderWidth,
            0, 1
        )
        value = min + percent * (max - min)
        
        -- Update fill and handle position with smooth animation
        fillWidth = percent * sliderWidth
        TweenService:Create(fill, TweenInfo.new(0.05), {
            Size = UDim2.new(0, fillWidth, 1, 0)
        }):Play()
        
        TweenService:Create(handle, TweenInfo.new(0.05), {
            Position = UDim2.new(0, fillWidth - 6, 0, -4)
        }):Play()
        
        -- Update value text
        valueText = string.format(format, value)
        valueLabel.Text = valueText
    end
    
    if ImGui.mouse.leftReleased then
        if ImGui.activeItem == sliderId then
            ImGui.activeItem = nil
            
            -- Reset handle size
            TweenService:Create(handle, TweenInfo.new(0.1), {
                Size = UDim2.new(0, 12, 0, 20),
                Position = UDim2.new(0, fillWidth - 6, 0, -4)
            }):Play()
        end
    end
    
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
    
    -- Create input box
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
    
    -- Check for interactions
    local isHovered = ImGui.mouse.position.X >= inputContainer.AbsolutePosition.X and
                     ImGui.mouse.position.X <= inputContainer.AbsolutePosition.X + inputWidth and
                     ImGui.mouse.position.Y >= inputContainer.AbsolutePosition.Y and
                     ImGui.mouse.position.Y <= inputContainer.AbsolutePosition.Y + inputHeight
    
    if isHovered then
        ImGui.hoveredItem = inputId
        -- Hover effect
        TweenService:Create(inputContainer, TweenInfo.new(0.1), {
            BackgroundColor3 = Color3.fromRGB(
                ImGui.style.inputBgColor.R * 255 + 10,
                ImGui.style.inputBgColor.G * 255 + 10,
                ImGui.style.inputBgColor.B * 255 + 10
            )
        }):Play()
    else
        -- Reset color
        TweenService:Create(inputContainer, TweenInfo.new(0.1), {
            BackgroundColor3 = ImGui.style.inputBgColor
        }):Play()
    end
    
    -- Focus effect
    inputBox.Focused:Connect(function()
        TweenService:Create(inputContainer, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(
                ImGui.style.inputBgColor.R * 255 + 15,
                ImGui.style.inputBgColor.G * 255 + 15, 
                ImGui.style.inputBgColor.B * 255 + 20
            )
        }):Play()
        
        -- Highlight the stroke
        TweenService:Create(inputContainer:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.2), {
            Color = ImGui.style.sliderColor,
            Transparency = 0
        }):Play()
    end)
    
    inputBox.FocusLost:Connect(function()
        TweenService:Create(inputContainer, TweenInfo.new(0.2), {
            BackgroundColor3 = ImGui.style.inputBgColor
        }):Play()
        
        -- Reset the stroke
        TweenService:Create(inputContainer:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.2), {
            Color = ImGui.style.borderColor,
            Transparency = 0.5
        }):Play()
    end)
    
    -- Capture text changes
    local newText = text
    inputBox.FocusLost:Connect(function()
        newText = inputBox.Text
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

return ImGui
