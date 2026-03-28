from PIL import Image

# caminho da imagem PNG gerada
img = Image.open("assets/icon_source2.png")

# tamanhos típicos incluídos dentro do .ico
sizes = [(16,16), (32,32), (48,48), (64,64), (128,128), (256,256)]

img.save("assets/app.ico", sizes=sizes)

print("Ícone salvo como assets/app.ico")