# SPDX-License-Identifier: GPL-2.0
# Astro Slide (MT6873 / CONNAC2X2 / A-die MT6635) CONSYS drivers.
# Sources: wolf109909/zinwa-q25-linux drivers/mediatek (vendor 5.10 drivers
# ported to 7.3), back-ported to 6.18; see README.astro.
# The vendor Makefiles below expect these variables; MTK_ROOT replaces
# their $(srctree)/drivers/misc/mediatek include root.
ifneq ($(CONFIG_MTK_WCN_CONSYS),)
export MTK_ROOT := $(srctree)/drivers/misc/mediatek-connectivity
export CONFIG_MTK_PLATFORM := mt6873
export MTK_PLATFORM := mt6873
export CONFIG_MTK_BTIF := m
export CONFIG_MTK_COMBO := m
export CONFIG_MTK_COMBO_WIFI := $(CONFIG_MTK_WCN_GEN4M)
export CONFIG_MTK_COMBO_CHIP := "CONSYS_6873"
export CONFIG_MTK_COMBO_CHIP_CONSYS_6873 := y
export CONFIG_MTK_CONNSYS_DEDICATED_LOG_PATH := y
export CONFIG_MTK_PMIC_CHIP_MT6359P := y
export CONFIG_MTK_COMBO_WIFI_HIF := axi
export MTK_COMBO_CHIP := SOC2_2X2
export WLAN_CHIP_ID := 6873
export WIFI_IP_SET := 3
export MTK_ANDROID_WMT := y
export MTK_ANDROID_EMI := y
export MTK_WLAN_SERVICE := yes

obj-m += btif/
obj-m += connectivity/
endif
