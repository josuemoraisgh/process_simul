import base64

input_file = "assets/splash_image.png"
output_file = "assets/splash_image_base64.txt"

with open(input_file, "rb") as f:
    encoded = base64.b64encode(f.read()).decode("utf-8")

with open(output_file, "w", encoding="utf-8") as txt:
    txt.write(encoded)

print(f"Base64 salvo em: {output_file}")
