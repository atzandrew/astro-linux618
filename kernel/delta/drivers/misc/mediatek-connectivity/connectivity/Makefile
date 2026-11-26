
ccflags-y += -I$(srctree)/ -I$(srctree)/drivers/mmc/core -I$(MTK_ROOT)/include/mt-plat -I$(MTK_ROOT)/q25inc -include $(MTK_ROOT)/q25inc/linux/q25_compat.h -Wno-error
MODULE_NAME := connadp
obj-m += $(MODULE_NAME).o
$(MODULE_NAME)-objs += common/connectivity_build_in_adapter.o
$(MODULE_NAME)-objs += common/wmt_build_in_adapter.o
$(MODULE_NAME)-objs += power_throttling/adapter.o
$(MODULE_NAME)-objs += power_throttling/core.o
$(MODULE_NAME)-objs += common/astro_emimpu_stub.o


obj-m += common/
obj-m += wlan/adaptor/
obj-$(CONFIG_MTK_COMBO_WIFI) += wlan/core/gen4m/
