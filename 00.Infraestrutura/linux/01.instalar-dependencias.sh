#!/usr/bin/env bash
# ==============================================================================
# SYNOPSIS
#   Instala ou atualiza todas as ferramentas necessárias para Kubernetes local
#   com k3d em Ubuntu/Debian.
#
# DESCRIPTION
#   - Docker Engine não instalado → instala via script oficial.
#   - k3d, kubectl e Helm → instalam via curl/apt se ausentes.
#   - Ferramentas já instaladas → prossegue sem alteração.
#
#   O Docker Engine é instalado por padrão. Use --install-docker-desktop para a
#   versão com GUI (recomendado para Ubuntu Desktop). Use --no-docker para pular.
#
# USAGE
#   sudo ./01.install-dependencies.sh                          # Docker Engine + k3d, kubectl, Helm e VS Code
#   sudo ./01.install-dependencies.sh --install-docker-desktop # Docker Desktop (GUI) + demais ferramentas
#        ./01.install-dependencies.sh --no-docker              # pula instalação do Docker
#
# NOTES
#   Execute com sudo para instalar Docker Engine, Docker Desktop ou VS Code.
#   k3d, kubectl e Helm são instalados no escopo do usuário (~/.local/bin ou /usr/local/bin).
# ==============================================================================

set -euo pipefail

INSTALL_DOCKER=true
INSTALL_DOCKER_DESKTOP=false

for arg in "$@"; do
  case "$arg" in
    --install-docker-desktop) INSTALL_DOCKER=false; INSTALL_DOCKER_DESKTOP=true ;;
    --no-docker)              INSTALL_DOCKER=false ;;
  esac
done

# Cores ANSI
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

write_step()    { echo -e "\n${CYAN}==> $1${RESET}"; }
write_success() { echo -e "    ${GREEN}OK: $1${RESET}"; }
write_warn()    { echo -e "    ${YELLOW}AVISO: $1${RESET}"; }
write_fail()    { echo -e "\n    ${RED}ERRO: $1${RESET}"; exit 1; }

# Detecta se um comando existe no PATH
command_exists() { command -v "$1" &>/dev/null; }

# ---------------------------------------------------------------------------
# Docker Engine — opcional, requer sudo
# ---------------------------------------------------------------------------
install_docker() {
  write_step "Docker Engine"

  if command_exists docker; then
    write_success "Docker já está instalado ($(docker --version 2>&1 | head -1)). Pulando."
    return
  fi

  if [[ $EUID -ne 0 ]]; then
    write_fail "A instalação do Docker requer sudo. Execute: sudo $0 --install-docker"
  fi

  write_step "Instalando Docker Engine via script oficial..."
  curl -fsSL https://get.docker.com | sh

  # Adiciona o usuário atual ao grupo docker para dispensar sudo no uso diário
  if [[ -n "${SUDO_USER:-}" ]]; then
    usermod -aG docker "$SUDO_USER"
    write_warn "Usuário '$SUDO_USER' adicionado ao grupo docker. Faça logout/login para aplicar."
  fi

  systemctl enable --now docker
  write_success "Docker Engine instalado e ativado."
}

# ---------------------------------------------------------------------------
# Docker Desktop — GUI para Ubuntu Desktop (https://docs.docker.com/desktop/linux/)
# ---------------------------------------------------------------------------
install_docker_desktop() {
  write_step "Docker Desktop (GUI)"

  if command_exists docker && docker context ls 2>/dev/null | grep -q desktop-linux; then
    write_success "Docker Desktop já está instalado. Pulando."
    return
  fi

  if [[ $EUID -ne 0 ]]; then
    write_fail "A instalação do Docker Desktop requer sudo. Execute: sudo $0 --install-docker-desktop"
  fi

  local ARCH
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]]  && ARCH="amd64"
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

  write_step "Instalando dependências do Docker Desktop..."
  apt-get update -qq >/dev/null
  apt-get install -y ca-certificates curl gnupg pass qemu-kvm >/dev/null

  # Docker Desktop exige acesso ao dispositivo KVM para virtualização
  # Ref: https://docs.docker.com/desktop/install/linux-install/#kvm-virtualization-support
  write_step "Configurando acesso ao KVM..."

  if ! grep -q "^kvm" /etc/group 2>/dev/null; then
    write_warn "Grupo 'kvm' não encontrado. Criando..."
    groupadd kvm
  fi

  local TARGET_USER="${SUDO_USER:-$USER}"
  if ! id -nG "$TARGET_USER" 2>/dev/null | grep -qw kvm; then
    usermod -aG kvm "$TARGET_USER"
    write_success "Usuário '$TARGET_USER' adicionado ao grupo kvm."
  else
    write_success "Usuário '$TARGET_USER' já pertence ao grupo kvm."
  fi

  # Regra udev persistente: garante que /dev/kvm sempre terá as permissões corretas
  # após cada boot, sem necessidade de ajuste manual
  local UDEV_RULE="/etc/udev/rules.d/99-kvm.rules"
  echo 'KERNEL=="kvm", GROUP="kvm", MODE="0660", OPTIONS+="static_node=kvm"' > "$UDEV_RULE"
  udevadm control --reload-rules
  udevadm trigger --name-match=kvm
  write_success "Regra udev criada em $UDEV_RULE (permissões aplicadas imediatamente e persistem no boot)."

  if [[ ! -e /dev/kvm ]]; then
    write_warn "/dev/kvm não encontrado. Verifique se a virtualização (VT-x/AMD-V) está habilitada na BIOS/UEFI."
  fi

  # O kernel ainda enxerga os grupos antigos até um novo login. Para que o Docker
  # Desktop funcione SEM logout, forçamos o grupo ativo na sessão do usuário alvo.
  write_warn "ATENÇÃO: faça logout e login novamente para que o grupo 'kvm' seja reconhecido pela sessão gráfica."
  write_warn "Alternativa sem logout: abra um terminal e execute 'newgrp kvm', depois inicie o Docker Desktop por lá."

  write_step "Baixando Docker Desktop (.deb)..."
  local DEB="/tmp/docker-desktop-${ARCH}.deb"
  curl -fsSLo "$DEB" \
    "https://desktop.docker.com/linux/main/${ARCH}/docker-desktop-${ARCH}.deb"

  write_step "Instalando pacote Docker Desktop..."
  apt-get install -y "$DEB" >/dev/null
  rm -f "$DEB"

  # Adiciona o usuário que invocou sudo ao grupo docker
  if [[ -n "${SUDO_USER:-}" ]]; then
    usermod -aG docker "$SUDO_USER"
    write_warn "Usuário '$SUDO_USER' adicionado ao grupo docker. Faça logout/login para aplicar."
  fi

  write_success "Docker Desktop instalado. Abra pelo menu de aplicativos ou com: systemctl --user start docker-desktop"
}

# ---------------------------------------------------------------------------
# k3d — instala via script oficial (https://k3d.io)
# ---------------------------------------------------------------------------
install_k3d() {
  write_step "k3d"

  if command_exists k3d; then
    write_success "k3d já instalado ($(k3d --version 2>&1 | head -1)). Pulando."
    return
  fi

  write_step "Instalando k3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  write_success "k3d instalado."
}

# ---------------------------------------------------------------------------
# kubectl — instala via binário oficial do Kubernetes
# ---------------------------------------------------------------------------
install_kubectl() {
  write_step "kubectl"

  if command_exists kubectl; then
    write_success "kubectl já instalado ($(kubectl version --client --short 2>&1 | head -1)). Pulando."
    return
  fi

  write_step "Instalando kubectl..."
  local ARCH
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

  local KUBE_VERSION
  KUBE_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)

  curl -fsSLo /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/${ARCH}/kubectl"
  chmod +x /usr/local/bin/kubectl
  write_success "kubectl ${KUBE_VERSION} instalado."
}

# ---------------------------------------------------------------------------
# Visual Studio Code — instala via repositório oficial da Microsoft
# ---------------------------------------------------------------------------
install_vscode() {
  write_step "Visual Studio Code"

  if command_exists code; then
    write_success "VS Code já instalado ($(code --version 2>&1 | head -1)). Pulando."
    return
  fi

  if [[ $EUID -ne 0 ]]; then
    write_fail "A instalação do VS Code requer sudo. Execute: sudo $0"
  fi

  write_step "Instalando VS Code via repositório Microsoft..."

  # Instala dependências mínimas e importa a chave GPG oficial
  apt-get install -y apt-transport-https gnupg2 >/dev/null
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg

  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
https://packages.microsoft.com/repos/code stable main" \
    > /etc/apt/sources.list.d/vscode.list

  apt-get update -qq >/dev/null
  apt-get install -y code >/dev/null
  write_success "VS Code instalado."
}

# ---------------------------------------------------------------------------
# Helm — instala via script oficial (https://helm.sh)
# ---------------------------------------------------------------------------
install_helm() {
  write_step "Helm"

  if command_exists helm; then
    write_success "Helm já instalado ($(helm version --short 2>&1 | head -1)). Pulando."
    return
  fi

  write_step "Instalando Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
  write_success "Helm instalado."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
write_step "Verificando pré-requisitos (curl)..."
if ! command_exists curl; then
  write_fail "curl não encontrado. Instale com: sudo apt-get install -y curl"
fi
write_success "curl disponível."

if $INSTALL_DOCKER_DESKTOP; then
  install_docker_desktop
elif $INSTALL_DOCKER; then
  install_docker
else
  write_step "Docker"
  write_warn "Pulando instalação do Docker (use --install-docker-desktop para GUI ou remova --no-docker para o Engine)."
fi

install_vscode
install_k3d
install_kubectl
install_helm

echo ""
echo -e "${GREEN}============================================================${RESET}"
echo -e "${GREEN}  Ferramentas instaladas/atualizadas com sucesso!${RESET}"
echo -e "${GREEN}============================================================${RESET}"
echo ""
echo -e "${YELLOW}PRÓXIMOS PASSOS:${RESET}"
echo -e "${YELLOW}  1. Recarregue o terminal: source ~/.bashrc${RESET}"
echo -e "${YELLOW}  2. Inicie o Docker:${RESET}"
echo -e "${YELLOW}     Docker Engine   : sudo systemctl start docker${RESET}"
echo -e "${YELLOW}     Docker Desktop  : systemctl --user start docker-desktop${RESET}"
echo -e "${YELLOW}  3. Execute: ./02.verify-installs.sh${RESET}"
echo ""
