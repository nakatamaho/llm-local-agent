# Dockerfile.emacs
# Emacs + aider container, connects to llama-server via llm-internal network

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    emacs-nox \
    git \
    curl \
    pipx \
    python3 \
    universal-ctags \
    ripgrep \
    sudo \
    ca-certificates \
    locales \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*

# Generate Japanese locale
RUN sed -i 's/# ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen ja_JP.UTF-8

ENV LANG=ja_JP.UTF-8
ENV LANGUAGE=ja_JP:ja
ENV LC_ALL=ja_JP.UTF-8

# Create user - handle pre-existing UID gracefully
ARG DOCKER_UID=1000
ARG DOCKER_GID=1000
ARG DOCKER_USER=docker

RUN set -eux; \
    existing="$(getent passwd ${DOCKER_UID} | cut -d: -f1 || true)"; \
    if [ -n "$existing" ]; then \
        usermod -l "${DOCKER_USER}" -d "/home/${DOCKER_USER}" -m "$existing"; \
        groupmod -n "${DOCKER_USER}" "$(id -gn ${DOCKER_UID})" 2>/dev/null || true; \
    else \
        groupadd -g "${DOCKER_GID}" "${DOCKER_USER}" 2>/dev/null || true; \
        useradd -u "${DOCKER_UID}" -g "${DOCKER_GID}" -m -s /bin/bash "${DOCKER_USER}"; \
    fi; \
    usermod -aG sudo "${DOCKER_USER}"; \
    echo "${DOCKER_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"${DOCKER_USER}"; \
    chmod 440 /etc/sudoers.d/"${DOCKER_USER}"

# Switch to non-root user for all subsequent steps
USER ${DOCKER_USER}
WORKDIR /home/${DOCKER_USER}

ENV PATH="/home/${DOCKER_USER}/.local/bin:$PATH"

# Install aider via pipx
RUN pipx install aider-chat==0.85.2

# Install aider.el
RUN mkdir -p ~/.emacs.d/lisp && \
    git clone https://github.com/tninja/aider.el.git ~/.emacs.d/lisp/aider.el

# Install Emacs packages
RUN emacs --batch \
    --eval "(require 'package)" \
    --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\") t)" \
    --eval "(add-to-list 'package-archives '(\"gnu\" . \"https://elpa.gnu.org/packages/\") t)" \
    --eval "(package-initialize)" \
    --eval "(package-refresh-contents)" \
    --eval "(dolist (pkg '(magit markdown-mode s dash spinner transient with-editor async)) (unless (package-installed-p pkg) (package-install pkg)))" \
    2>&1 | tail -10

# Emacs init
RUN mkdir -p ~/.emacs.d && cat > ~/.emacs.d/init.el << 'INITEOF'
;; ── Path ────────────────────────────────────────────────────────────────────
(add-to-list 'exec-path (expand-file-name "~/.local/bin"))
(setenv "PATH" (concat (expand-file-name "~/.local/bin") ":" (getenv "PATH")))

;; ── Japanese support ─────────────────────────────────────────────────────────
(set-language-environment "Japanese")
(prefer-coding-system 'utf-8)
(set-default-coding-systems 'utf-8)
(set-terminal-coding-system 'utf-8)
(set-keyboard-coding-system 'utf-8)
(setenv "LANG" "ja_JP.UTF-8")
(setenv "LC_ALL" "ja_JP.UTF-8")

;; ── Disable all colors and visual decoration ─────────────────────────────────
(setq-default font-lock-mode nil)
(global-font-lock-mode -1)          ; disable syntax highlighting
(setq font-lock-global-modes nil)
(when (fboundp 'global-hi-lock-mode) (global-hi-lock-mode -1))

;; Disable colors in shell/comint buffers (where aider runs)
(setq ansi-color-for-comint-mode 'filter)  ; strip ANSI escape codes
(add-hook 'shell-mode-hook
          (lambda () (face-remap-add-relative 'default :foreground "unspecified")))
(add-hook 'comint-mode-hook
          (lambda () (setq-local ansi-color-for-comint-mode 'filter)))

;; Strip ANSI codes from aider output
(add-hook 'comint-output-filter-functions 'ansi-color-process-output)

;; ── aider ────────────────────────────────────────────────────────────────────
(add-to-list 'load-path (expand-file-name "~/.emacs.d/lisp/aider.el"))
(require 'aider)
(setenv "NO_COLOR" "1")
(setenv "TERM" "dumb")

(setq aider-args '("--model" "openai/Qwen3.5-35B-A3B"
                   "--openai-api-base" "http://172.30.0.10:8080/v1"
                   "--openai-api-key" "dummy"
                   "--no-check-update"
                   "--no-show-model-warnings"
                   "--no-show-release-notes"
                   "--no-fancy-input"
                   "--no-pretty"
                   "--map-tokens" "1024"
                   "--max-chat-history-tokens" "4096"
                   "--edit-format" "diff"
                   "--auto-commits"
                   "--no-auto-lint"))

(setenv "OPENAI_API_KEY" "dummy")
(setenv "OPENAI_API_BASE" "http://172.30.0.10:8080/v1")

;; ── Key bindings ─────────────────────────────────────────────────────────────
(global-set-key (kbd "C-c a a") 'aider-run-aider)
(global-set-key (kbd "C-c a f") 'aider-add-current-file)
(global-set-key (kbd "C-c a q") 'aider-ask)
(global-set-key (kbd "C-c a c") 'aider-code-change)
(global-set-key (kbd "C-c a d") 'aider-diff)
(global-set-key (kbd "C-c a u") 'aider-undo-last-change)
INITEOF

WORKDIR /workspace
CMD ["emacs"]
