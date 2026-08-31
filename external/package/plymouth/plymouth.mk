################################################################################
#
# plymouth
#
################################################################################

PLYMOUTH_VERSION = 26.134.222
PLYMOUTH_SOURCE = plymouth-$(PLYMOUTH_VERSION).tar.xz
PLYMOUTH_SITE = https://www.freedesktop.org/software/plymouth/releases
PLYMOUTH_LICENSE = GPL-2.0+
PLYMOUTH_LICENSE_FILES = COPYING
PLYMOUTH_DEPENDENCIES = \
	host-gettext \
	host-pkgconf \
	$(BR2_PYTHON3_HOST_DEPENDENCY) \
	freetype \
	libdrm \
	libevdev \
	libpng \
	libxkbcommon \
	udev \
	xkeyboard-config

PLYMOUTH_CONF_OPTS = \
	-Dboot-tty=/dev/tty1 \
	-Ddocs=false \
	-Ddrm=true \
	-Dfreetype=enabled \
	-Dgtk=disabled \
	-Dpango=disabled \
	-Drelease-file=/etc/os-release \
	-Dshutdown-tty=/dev/tty63 \
	-Dsystemd-integration=false \
	-Dtracing=false \
	-Dudev=enabled \
	-Dupstart-monitoring=false

$(eval $(meson-package))
