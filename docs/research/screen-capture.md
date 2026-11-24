# Research: Screenshot capture

## Approach
- `System.Drawing.Graphics.CopyFromScreen` → Bitmap → base64 PNG
- Send as image to vision-capable Ollama model

## Use cases
- UIA can't read (images, canvases, RDP, broken layouts)
- Visual "what am I looking at" summaries

## Considerations
- Capture active window bounds vs full screen
- Image size / token cost for vision models
- Privacy: same denylist as UIA
