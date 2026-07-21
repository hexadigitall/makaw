from PIL import Image, ImageDraw, ImageFont
import struct, os

COLOR = (129, 140, 248)  # accent indigo
BG = (26, 27, 46)         # dark bg
SIZE = 512

def create_svg():
    """Write an SVG string for the M logo."""
    return '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <rect width="512" height="512" rx="100" fill="#1a1b2e"/>
  <path d="M140 380V132l116 140 116-140v248" stroke="#818cf8" stroke-width="48" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>'''

def render_m(size=512, padding=60, stroke_width=44):
    """Render the M logo with Pillow."""
    img = Image.new('RGBA', (size, size), (0,0,0,0))
    draw = ImageDraw.Draw(img)
    rr = size // 5

    # rounded rect background
    bg_color = BG + (255,)
    draw.rounded_rectangle([(0,0),(size-1,size-1)], radius=rr, fill=bg_color)

    m = size - 2*padding
    top = padding
    bottom = size - padding
    left = padding
    right = size - padding
    mid_x = size // 2

    # three segments of M: left leg, middle V, right leg
    pts = [
        (left, bottom),          # bottom-left
        (left, top),             # top-left
        (mid_x, bottom - m*0.38), # middle point (V bottom)
        (right, top),            # top-right
        (right, bottom),         # bottom-right
    ]

    # draw as thick polylines
    draw.line([pts[0], pts[1]], fill=COLOR, width=stroke_width, joint='curve')
    draw.line([pts[1], pts[2]], fill=COLOR, width=stroke_width, joint='curve')
    draw.line([pts[2], pts[3]], fill=COLOR, width=stroke_width, joint='curve')
    draw.line([pts[3], pts[4]], fill=COLOR, width=stroke_width, joint='curve')

    return img

# --- generate assets ---
svg_content = create_svg()
with open('assets/makaw_logo.svg', 'w') as f:
    f.write(svg_content)
print('SVG created')

# 512x512 PNG
img_512 = render_m(512)
img_512.save('assets/makaw_logo.png')
print('PNG 512x512 created')

# 256x256 PNG
img_256 = img_512.resize((256,256), Image.LANCZOS)
img_256.save('assets/makaw_logo_256.png')

# 128x128 PNG
img_128 = img_512.resize((128,128), Image.LANCZOS)
img_128.save('assets/makaw_logo_128.png')

# 64x64 PNG
img_64 = img_512.resize((64,64), Image.LANCZOS)
img_64.save('assets/makaw_logo_64.png')

# 32x32 PNG
img_32 = img_512.resize((32,32), Image.LANCZOS)
img_32.save('assets/makaw_logo_32.png')

# 16x16 PNG
img_16 = img_512.resize((16,16), Image.LANCZOS)
img_16.save('assets/makaw_logo_16.png')

# ICO: combine 256, 128, 64, 32, 16
sizes_dict = {
    256: img_256,
    128: img_128,
    64:  img_64,
    32:  img_32,
    16:  img_16,
}
# Pillow can save ICO directly
img_256.save('assets/makaw_logo.ico', format='ICO', sizes=[(256,256),(128,128),(64,64),(32,32),(16,16)])
print('ICO created')

# also try ImageMagick convert for favicon.ico
os.system('convert assets/makaw_logo_32.png assets/makaw_favicon.ico 2>/dev/null')
print('Favicon ICO created via ImageMagick')

print('All assets generated in assets/')
