# 🖤 Notch for macOS

Una experiencia interactiva y minimalista estilo **Dynamic Island / Notch** diseñada para macOS. Transforma el área superior de tu pantalla en un centro de productividad, música, cámara y utilidades rápidas.

![macOS 12+](https://img.shields.io/badge/macOS-12.0%2B-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

---

## ✨ Características

* 🎵 **Now Playing**: Integración y controles en vivo para Spotify, Apple Music, YouTube y navegadores. Controles completos: anterior, play/pause y siguiente. Muestra carátula, título, artista y barra de progreso sin bloqueos de permisos.
* 🪄 **Eliminador de Fondos IA Nativo**: Arrastra cualquier imagen (JPG, PNG, WebP, HEIC) al estante y haz clic para quitar el fondo al instante con el motor neuronal nativo de Apple Vision en macOS. Descarga automáticamente el PNG transparente en tu carpeta `~/Downloads`.
* 🪞 **Mini Espejo y Aro de Luz**: Espejo circular en vivo con tu cámara FaceTime/webcam. Incluye control de aro de luz en pantalla con temperatura cálida y fría para iluminar tu rostro.
* 📦 **Estante de Archivos y AirDrop**: Almacena imágenes arrastrándolas al Notch, o suéltalas en la zona derecha para enviarlas inmediatamente por AirDrop.
* 📌 **Anclaje Inteligente con Doble Clic**: Botón de anclar en la barra superior del Notch. Al estar anclado, con hacer doble clic aparece el botón para desanclar y contraerlo.
* ⚡ **Ultraligero y Optimizado**: Pesa solo 2.4 MB (más de 98% de reducción de tamaño) sin modelos externos pesados ni consumo de batería.

---

## 🚀 Descarga e Instalación (Para tu MacBook)

Para instalarlo en cualquier MacBook o Mac en 30 segundos:

1. Ve a **[Releases](../../releases/latest)** y descarga el archivo **`Notch.zip`** (solo 1.3 MB).
2. Haz doble clic en `Notch.zip` para descomprimirlo y obtener **`Notch.app`**.
3. Arrastra **`Notch.app`** a tu carpeta de **Aplicaciones**.
4. **Primera apertura**:
   * Haz **clic derecho** sobre `Notch.app` y selecciona **Abrir**.
   * Haz clic en **Abrir** en el aviso de seguridad de macOS.
   * *(O ejecuta en la Terminal: `xattr -cr /Applications/Notch.app`)*.

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
