Customize = {}

-- General
Customize.Command           = 'shotmaker'
Customize.MenuCommand       = 'wardrobe'
Customize.RoutingBucket     = 999

Customize.ScreenshotQuality = 0.92          -- 0.0–1.0 (webp/jpg only)
Customize.ScreenshotFormat  = 'png'         -- 'png' | 'webp' | 'jpg'
Customize.TransparentBg     = true          -- chroma key removal (png only)
Customize.ScreenshotWidth   = 512
Customize.ScreenshotHeight  = 512

Customize.BackendURL        = 'http://127.0.0.1:3959/upload'

Customize.StudioCoords      = vector3(0.0, 0.0, -150.0)
Customize.StudioHeading     = 180.0

Customize.WaitAfterApply    = 500           -- ms
Customize.WaitAfterCapture  = 300           -- ms
Customize.TextureLoadWait   = 600           -- ms
Customize.CaptureAllTextures = false        -- true = all textures, false = texture 0 only

-- Batch / Performance
Customize.BatchSize         = 10
Customize.BatchPauseWait    = 2000          -- ms
Customize.GCInterval        = 20

-- Chroma Key Screen
Customize.ChromaKeyColor    = 'magenta'          -- 'green' | 'magenta'

Customize.GreenScreen = {
    width       = 5.0,
    depth       = 5.0,
    height      = 3.5,
    floorOffset = -1.0,
}

-- Auto-set screen color from preset (do not edit manually)
Customize.GreenScreen.color = Customize.ChromaKeyColor == 'magenta'
    and { r = 255, g = 0, b = 255 }
    or  { r = 0,   g = 177, b = 64 }

-- Studio Lights
Customize.StudioLights = {
    { offset = vector3(0.0, 2.5, 1.0),  range = 8.0, intensity = 3.0 },
    { offset = vector3(-2.5, 0.0, 1.0), range = 5.0, intensity = 2.0 },
    { offset = vector3(2.5, 0.0, 1.0),  range = 5.0, intensity = 2.0 },
    { offset = vector3(0.0, -1.5, 1.0), range = 4.0, intensity = 1.5 },
    { offset = vector3(0.0, 0.0, 3.0),  range = 6.0, intensity = 2.5 },
}

-- Camera Presets  (fov, zPos, rotation, dist)
Customize.CameraPresets = {
    head        = { fov = 30.0, zPos = 0.65,  rotation = vector3(0.0, 0.0, 120.0),  dist = 1.2 },
    torso       = { fov = 55.0, zPos = 0.3,   rotation = vector3(0.0, 0.0, 155.0),  dist = 1.2 },
    legs        = { fov = 60.0, zPos = -0.46, rotation = vector3(0.0, 0.0, 155.0),  dist = 1.2 },
    shoes       = { fov = 40.0, zPos = -0.85, rotation = vector3(0.0, 0.0, 120.0),  dist = 1.2 },
    bags        = { fov = 40.0, zPos = 0.3,   rotation = vector3(0.0, 0.0, -25.0),  dist = 1.2 },
    accessories = { fov = 45.0, zPos = 0.3,   rotation = vector3(0.0, 0.0, 155.0),  dist = 1.2 },
    hats        = { fov = 30.0, zPos = 0.75,  rotation = vector3(0.0, 0.0, 120.0),  dist = 1.2 },
    glasses     = { fov = 20.0, zPos = 0.7,   rotation = vector3(0.0, 0.0, 120.0),  dist = 1.2 },
    ears        = { fov = 20.0, zPos = 0.675, rotation = vector3(0.0, 0.0, 237.5),  dist = 1.2 },
    watches     = { fov = 20.0, zPos = 0.03,  rotation = vector3(0.0, 0.0, 59.0),   dist = 1.2 },
    bracelets   = { fov = 20.0, zPos = 0.03,  rotation = vector3(0.0, 0.0, 250.0),  dist = 1.2 },
}

-- Clothing Categories (componentId → camera preset)
Customize.Categories = {
    { componentId = 1,  label = 'Mask',          camera = 'head'        },
    { componentId = 3,  label = 'Arms / Gloves', camera = 'torso'       },
    { componentId = 4,  label = 'Pants',         camera = 'legs'        },
    { componentId = 5,  label = 'Bags',          camera = 'bags'        },
    { componentId = 6,  label = 'Shoes',         camera = 'shoes'       },
    { componentId = 7,  label = 'Accessories',   camera = 'accessories' },
    { componentId = 8,  label = 'Undershirt',    camera = 'torso'       },
    { componentId = 9,  label = 'Body Armor',    camera = 'torso'       },
    { componentId = 10, label = 'Decals',        camera = 'torso'       },
    { componentId = 11, label = 'Tops',          camera = 'torso'       },
}

-- Prop Categories (propId → camera preset)
Customize.PropCategories = {
    { propId = 0, label = 'Hats',      camera = 'hats'      },
    { propId = 1, label = 'Glasses',   camera = 'glasses'   },
    { propId = 2, label = 'Ears',      camera = 'ears'      },
    { propId = 6, label = 'Watches',   camera = 'watches'   },
    { propId = 7, label = 'Bracelets', camera = 'bracelets' },
}
