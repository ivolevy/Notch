# 🖤 Notch for macOS

Una experiencia interactiva y minimalista estilo **Dynamic Island / Notch** diseñada para macOS. Transforma el área superior de tu pantalla en un centro de productividad, música, cámara y utilidades rápidas.

![macOS 12+](https://img.shields.io/badge/macOS-12.0%2B-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

---

## ✨ Características

* 🎵 **Now Playing**: Integración y controles en vivo para Spotify, Apple Music y navegadores (Arc, Safari, Chrome). Muestra carátula, título, artista y barra de progreso.
* 🪄 **Eliminador de Fondos IA (100% Precisión)**: Arrastra imágenes al estante y haz clic para quitar el fondo al instante con el modelo neuronal SOTA **RMBG-1.4**. Descarga automáticamente el PNG transparente en tu carpeta `~/Downloads`.
* 🪞 **Mini Espejo y Aro de Luz**: Espejo circular en vivo con tu cámara FaceTime/webcam. Incluye control de aro de luz en pantalla con temperatura cálida y fría para iluminar tu rostro.
* 📦 **Estante de Archivos y AirDrop**: Almacena temporalmente imágenes arrastrándolas al Notch, o suéltalas en la zona derecha para enviarlas inmediatamente por AirDrop. Al pasar el mouse sobre una imagen, aparece una `x` discreta para borrarla.
* 📌 **Anclaje Inteligente**: Haz clic derecho en el Notch para "Anclar Notch" y mantenerlo siempre desplegado mientras trabajas.

---

## 🚀 Instalación rápida (Sin compilar nada)

Para instalarlo en cualquier MacBook o Mac:

1. Ve a la pestaña de **[Releases](../../releases)** del repositorio.
2. Descarga el archivo **`Notch.zip`** de la última versión.
3. Haz doble clic en `Notch.zip` para descomprimirlo: aparecerá la app **`Notch.app`**.
4. Arrastra **`Notch.app`** a tu carpeta de **Aplicaciones**.
5. **Primera apertura (Gatekeeper de macOS)**:
   * Al ser una aplicación independiente, la primera vez haz **clic derecho** sobre `Notch.app` y selecciona **Abrir**.
   * Haz clic en el botón **Abrir** en el diálogo de seguridad de macOS.
   * *(O desde la Terminal: `xattr -cr /Applications/Notch.app`)*.

¡Listo! El Notch aparecerá en la parte superior central de tu pantalla.

---

## 🛠️ Compilación desde el código fuente

Si deseas compilar la aplicación tú mismo:

```bash
# Clonar el repositorio
git clone https://github.com/ivolevy/Notch.git
cd Notch

# Compilar, empaquetar y ejecutar
chmod +x build_and_run.sh
./build_and_run.sh
```

El script `./build_and_run.sh`:
- Compila automáticamente el binario en modo Release con `swiftc`.
- Descarga el modelo neuronal ONNX si no está presente.
- Crea y firma ad-hoc el bundle `Notch.app`.
- Genera el paquete `Notch.zip`.
- Lanza la aplicación en macOS.

---

## 🔒 Privacidad y Permisos

* **Cámara**: Se solicita exclusivamente para la función de espejo circular. La cámara se apaga por completo al colapsar el Notch o cambiar de pestaña.
* **Apple Events**: Permite consultar qué canción se está reproduciendo en Spotify y Apple Music.
* **Procesamiento Local**: La eliminación de fondos mediante IA y la visión por computadora se ejecutan **100% de manera local y offline** en tu Mac. Ninguna imagen o dato sale de tu equipo.

---

## 👨‍💻 Autor

Desarrollado con dedicación por **Ivan Levy** ([@ivolevy](https://github.com/ivolevy)).
