#!/usr/bin/env bash
set -euo pipefail

# =========================================================================
# Build script para KebianOS
#
#   ./build-kebianos.sh                          -> build rápido de prueba,
#                                                    usa el último --volume
#                                                    guardado (o el default)
#   ./build-kebianos.sh --volume "1.2 RC1"       -> build de prueba con
#                                                    volumen custom (se le
#                                                    agrega "Beta" si no
#                                                    trae sufijo conocido)
#   ./build-kebianos.sh --release --volume "1.2 Final"
#                                                 -> build de release:
#                                                    --volume es OBLIGATORIO,
#                                                    se usa tal cual (sin
#                                                    agregarle "Beta"), y se
#                                                    sube el nivel de
#                                                    compresión del squashfs
#   ./build-kebianos.sh --release --push -m "release: v1.2"
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/.iso-version"
DEFAULT_VERSION="KebianOS 1.1 Beta"

DISTRIBUTION="trixie"
ARCH="amd64"

# --- Estado que van llenando los flags -----------------------------------
RELEASE_MODE=false
VOLUME_PROVIDED=false
VOLUME_ARG=""
PUSH_TO_GIT=false
GIT_BRANCH="main"
COMMIT_MESSAGE="build: update ISO"

# --- Manejo del archivo oculto con el último volumen usado ---------------
ensure_version_file() {
  if [[ ! -f "$VERSION_FILE" || ! -s "$VERSION_FILE" ]]; then
    printf '%s\n' "$DEFAULT_VERSION" > "$VERSION_FILE"
  fi
}

read_last_version() {
  ensure_version_file
  local last_value
  last_value="$(tr -d '\r\n' < "$VERSION_FILE")"
  if [[ -n "$last_value" ]]; then
    echo "$last_value"
  else
    echo "$DEFAULT_VERSION"
  fi
}

# Se usa SOLO para builds normales (no --release): agrega prefijo
# "KebianOS " y sufijo "Beta" si el usuario no puso ningún sufijo conocido.
normalize_version() {
  local value="$1"

  if [[ -z "$value" ]]; then
    echo "$DEFAULT_VERSION"
    return
  fi

  if [[ "$value" =~ ^KebianOS[[:space:]] ]]; then
    if [[ "$value" =~ (Beta|Alpha|RC|Final)$ ]]; then
      echo "$value"
    else
      echo "${value} Beta"
    fi
    return
  fi

  if [[ "$value" =~ (Beta|Alpha|RC|Final)$ ]]; then
    echo "KebianOS $value"
  else
    echo "KebianOS $value Beta"
  fi
}

# Se usa SOLO en modo --release: no toca el sufijo, solo asegura que
# empiece con "KebianOS " si el usuario no lo escribió.
normalize_volume_for_release() {
  local value="$1"
  if [[ "$value" =~ ^KebianOS[[:space:]] ]]; then
    echo "$value"
  else
    echo "KebianOS $value"
  fi
}

usage() {
  cat <<EOF
Uso: $0 [opciones]

Opciones:
  -v, --volume "NOMBRE"   Nombre del --iso-volume. En modo normal se le
                          agrega " Beta" si no traes sufijo conocido.
                          En modo --release se usa tal cual (obligatorio).
      --release           Build de release: exige --volume, comprime el
                          squashfs con xz al nivel 9 (máxima compresión,
                          más lento) y NO desactiva los checksums (build
                          más lento pero ISO más chica y verificable).
  -p, --push              git add/commit/push al terminar.
  -m, --message "MSJ"     Mensaje del commit si se usa --push.
  -b, --branch "NOMBRE"   Rama de git (por defecto: main).
  -h, --help              Muestra esta ayuda.

Ejemplos:
  $0
  $0 --volume "1.2 RC1"
  $0 --release --volume "1.2 Final" --push -m "release: v1.2"
EOF
}

# --- Parseo de flags -------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--volume)
      VOLUME_ARG="$2"
      VOLUME_PROVIDED=true
      shift 2
      ;;
    --release)
      RELEASE_MODE=true
      shift
      ;;
    -p|--push)
      PUSH_TO_GIT=true
      shift
      ;;
    -m|--message)
      COMMIT_MESSAGE="$2"
      shift 2
      ;;
    -b|--branch)
      GIT_BRANCH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Opción desconocida: $1"
      usage
      exit 1
      ;;
  esac
done

# --- Resolver el --iso-volume final ---------------------------------------
if [[ "$RELEASE_MODE" == true ]]; then
  if [[ "$VOLUME_PROVIDED" != true ]]; then
    echo "Error: --release requiere que pases --volume explícitamente." >&2
    echo "Ejemplo: $0 --release --volume \"1.2 Final\"" >&2
    exit 1
  fi
  ISO_VOLUME="$(normalize_volume_for_release "$VOLUME_ARG")"
else
  if [[ "$VOLUME_PROVIDED" == true ]]; then
    ISO_VOLUME="$(normalize_version "$VOLUME_ARG")"
  else
    ISO_VOLUME="$(read_last_version)"
  fi
fi

# --- Flags extra de compresión / checksums según el modo -------------------
# Modo prueba (default): squashfs con lz4 (el algoritmo más rápido de
# comprimir de los que soporta live-build) y sin checksums, para que cada
# build sea lo más rápido posible mientras iteras.
# Modo release: squashfs con xz (el que mejor comprime, aunque más lento)
# al nivel de compresión más alto (9), y dejamos los checksums en su valor
# por defecto para verificar la integridad del ISO final.
EXTRA_LB_CONFIG_ARGS=()
if [[ "$RELEASE_MODE" == true ]]; then
  EXTRA_LB_CONFIG_ARGS+=(--chroot-squashfs-compression-type xz --chroot-squashfs-compression-level 9)
else
  EXTRA_LB_CONFIG_ARGS+=(--chroot-squashfs-compression-type lz4 --checksums none)
fi

echo "==> Generando ISO con:"
echo "  modo: $([[ "$RELEASE_MODE" == true ]] && echo release || echo prueba)"
echo "  distro: $DISTRIBUTION"
echo "  arch: $ARCH"
echo "  iso-volume: $ISO_VOLUME"

action() {
  lb clean
  lb config \
    --distribution "$DISTRIBUTION" \
    --architectures "$ARCH" \
    --binary-images iso-hybrid \
    --bootloaders "grub-efi syslinux" \
    --archive-areas "main contrib non-free non-free-firmware" \
    --iso-application "KebianOS" \
    --iso-volume "$ISO_VOLUME" \
    --iso-publisher "KebianOS Team" \
    --iso-preparer "KebianOS" \
    "${EXTRA_LB_CONFIG_ARGS[@]}"

  lb build

  # Solo guardamos el volumen como "default" en modo prueba, para no
  # que un build de release puntual te cambie el valor por defecto de
  # tus builds diarios. Si quieres que SIEMPRE se guarde, quita el "if".
  if [[ "$RELEASE_MODE" != true ]]; then
    printf '%s\n' "$ISO_VOLUME" > "$VERSION_FILE"
  fi
}

action

if [[ "$PUSH_TO_GIT" == true ]]; then
  echo "==> Subiendo cambios a GitHub"
  if [[ -n "$(git status --porcelain)" ]]; then
    git add -A
    git commit -m "$COMMIT_MESSAGE" || true
    git push origin "$GIT_BRANCH"
  else
    echo "No hay cambios para subir."
  fi
fi

echo "==> Proceso finalizado."