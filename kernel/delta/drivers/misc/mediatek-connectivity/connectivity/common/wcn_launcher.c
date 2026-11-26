// SPDX-License-Identifier: GPL-2.0
/*
 * In-kernel stand-in for the stock Android wmt_loader + wmt_launcher,
 * Astro Slide (MT6873, CONNAC2X2, A-die MT6635). Ported from the Cosmo
 * (cosmo-linux618, MT6771) version, plus the "srh_rom_patch" request that
 * the CONNAC2 platforms issue.
 *
 * On stock the WMT driver is driven by two vendor daemons:
 *   wmt_loader:   /dev/wmtdetect COMBO_IOCTL_GET_SOC_CHIP_ID, then
 *                 COMBO_IOCTL_SET_CHIP_ID with that ID (no external combo
 *                 chip), then COMBO_IOCTL_DO_MODULE_INIT, which in
 *                 kernel-object mode runs mtk_wcn_common_drv_init().
 *   wmt_launcher: /dev/stpwmt WMT_IOCTL_SET_STP_MODE (BTIF full mode, FM over
 *                 the common interface), then answers the WMT core's requests:
 *                 "srh_patch"     -> WMT_IOCTL_SET_PATCH_NUM/_SET_PATCH_INFO
 *                                    (MCU ROM patch, downloaded over STP)
 *                 "srh_rom_patch" -> WMT_IOCTL_SET_ROM_PATCH_INFO per type
 *                                    (RAM code copied into the EMI window)
 *                 and writes "ok".
 *
 * Header rule (stock launcher, also used by the Cosmo port): byte 24 is
 * (count << 4) | seq, the address bytes are 0 + header bytes 25..27.
 * Astro stock files (vendor/firmware, 2026-11-25):
 *   soc2_0_patch_mcu_3b_1_hdr.bin  11 c0 01 00 -> 0x0001c000 (= gen4m
 *                                  SOC2_2X2_PATCH_START_ADDR)
 *   soc2_0_ram_mcu_3b_1_hdr.bin    11 00 00 f0 -> 0xf0000000
 *   soc2_0_ram_wifi_3b_1_hdr.bin   11 00 1d f0 -> 0xf01d0000 (= gen4m
 *                                  mt6873 WIFI_EMI_MEM_OFFSET 0x1D0000)
 *   soc2_0_ram_bt_3b_1_hdr.bin     11 00 11 f0 -> 0xf0110000
 * zinwa-q25-linux hard-codes its own MT6789 values (soc2_2 *_1e_1, Wi-Fi
 * 0x2a, BT 0x17); reading the header avoids carrying those over.
 */

#include <linux/firmware.h>
#include <linux/kthread.h>
#include <linux/slab.h>
#include <linux/string.h>
#include "osal_typedef.h"
#include "osal.h"
#include "wmt_dev.h"
#include "wmt_core.h"
#include "wmt_lib.h"
#include "wmt_exp.h"
#include "wmt_plat.h"
#include "wcn_launcher.h"
#include "wmt_detect.h"
#include "mtk_wcn_cmb_stub.h"

extern UINT32 hif_info;	/* wmt_dev.c, set once the STP mode is configured */

/* "srh_patch": MCU ROM patch list (one file on this board). */
static const char *const wcn_patches[] = {
	"soc2_0_patch_mcu_3b_1_hdr.bin",
};

/* "srh_rom_patch": RAM code per WMT driver type. */
static const struct {
	UINT32 type;
	const char *name;
} wcn_rom_patches[] = {
	{ WMTDRV_TYPE_BT,   "soc2_0_ram_bt_3b_1_hdr.bin" },
	{ WMTDRV_TYPE_WIFI, "soc2_0_ram_wifi_3b_1_hdr.bin" },
	{ WMTDRV_TYPE_WMT,  "soc2_0_ram_mcu_3b_1_hdr.bin" },
};

#define WCN_HDR_SEQ	24	/* (count << 4) | seq */
#define WCN_HDR_ADDR	25	/* address bytes 1..3; byte 0 is 0 */

static P_WMT_PATCH_INFO wcn_patch_info;
static struct task_struct *wcn_launcher_task;

/* Body of the stock WMT_IOCTL_SET_STP_MODE handler (wmt_dev.c). */
static INT32 wcn_set_stp_mode(ULONG arg)
{
	P_OSAL_OP pOp;
	P_WMT_HIF_CONF pHif;
	INT32 iRet;

	if (hif_info == 1)
		return 0;

	iRet = wmt_lib_set_hif(arg);
	if (iRet) {
		pr_err("wcn-launcher: wmt_lib_set_hif(0x%lx) fail %d\n", arg, iRet);
		return iRet;
	}
	pOp = wmt_lib_get_free_op();
	if (!pOp) {
		pr_err("wcn-launcher: no free op\n");
		return -ENOMEM;
	}
	pOp->op.opId = WMT_OPID_HIF_CONF;
	pHif = wmt_lib_get_hif();
	osal_memcpy(&pOp->op.au4OpData[0], pHif, sizeof(WMT_HIF_CONF));
	pOp->op.u4InfoBit = WMT_OP_HIF_BIT;
	pOp->signal.timeoutValue = 0;
	if (wmt_lib_put_act_op(pOp) == MTK_WCN_BOOL_FALSE) {
		pr_err("wcn-launcher: WMT_OPID_HIF_CONF failed\n");
		return -EFAULT;
	}
	hif_info = 1;
	pr_info("wcn-launcher: STP mode 0x%lx set (BTIF full, FM common)\n", arg);
	return 0;
}

/* Read a firmware header: count/seq byte and the 4 address bytes. */
static INT32 wcn_read_hdr(const char *name, UINT32 *cnt, UINT32 *seq,
			  UINT8 addr[4])
{
	const struct firmware *fw;
	INT32 ret;

	ret = request_firmware(&fw, name, NULL);
	if (ret) {
		pr_err("wcn-launcher: %s: request_firmware %d\n", name, ret);
		return ret;
	}
	if (fw->size < sizeof(WMT_PATCH)) {
		pr_err("wcn-launcher: %s too small (%zu)\n", name, fw->size);
		release_firmware(fw);
		return -EINVAL;
	}
	*cnt = fw->data[WCN_HDR_SEQ] >> 4;
	*seq = fw->data[WCN_HDR_SEQ] & 0xf;
	addr[0] = 0;
	addr[1] = fw->data[WCN_HDR_ADDR];
	addr[2] = fw->data[WCN_HDR_ADDR + 1];
	addr[3] = fw->data[WCN_HDR_ADDR + 2];
	pr_info("wcn-launcher: %s count %u seq %u address %02x %02x %02x %02x (%zu bytes)\n",
		name, *cnt, *seq, addr[0], addr[1], addr[2], addr[3], fw->size);
	release_firmware(fw);
	return 0;
}

static INT32 wcn_srh_patch(VOID)
{
	const UINT32 n = ARRAY_SIZE(wcn_patches);
	P_WMT_PATCH_INFO info;
	UINT32 i, cnt, seq;
	UINT8 addr[4];
	INT32 ret;

	info = kcalloc(n, sizeof(*info), GFP_KERNEL);
	if (!info)
		return -ENOMEM;

	for (i = 0; i < n; i++) {
		ret = wcn_read_hdr(wcn_patches[i], &cnt, &seq, addr);
		if (ret)
			goto fail;
		if (cnt != n || seq == 0 || seq > n || info[seq - 1].dowloadSeq) {
			pr_err("wcn-launcher: %s: count %u seq %u, expected %u patches\n",
			       wcn_patches[i], cnt, seq, n);
			ret = -EINVAL;
			goto fail;
		}
		info[seq - 1].dowloadSeq = seq;
		memcpy(info[seq - 1].addRess, addr, sizeof(addr));
		strscpy(info[seq - 1].patchName, wcn_patches[i],
			sizeof(info[seq - 1].patchName));
	}

	kfree(wcn_patch_info);
	wcn_patch_info = info;
	wmt_lib_set_patch_num(n);		/* WMT_IOCTL_SET_PATCH_NUM */
	wmt_lib_set_patch_info(wcn_patch_info);	/* WMT_IOCTL_SET_PATCH_INFO */
	return 0;
fail:
	kfree(info);
	return ret;
}

static INT32 wcn_srh_rom_patch(VOID)
{
	struct wmt_rom_patch_info info;
	UINT32 i, cnt, seq;
	INT32 ret;

	for (i = 0; i < ARRAY_SIZE(wcn_rom_patches); i++) {
		memset(&info, 0, sizeof(info));
		ret = wcn_read_hdr(wcn_rom_patches[i].name, &cnt, &seq, info.addRess);
		if (ret)
			return ret;
		if (cnt != 1 || seq != 1) {
			pr_err("wcn-launcher: %s: count %u seq %u, expected 1/1\n",
			       wcn_rom_patches[i].name, cnt, seq);
			return -EINVAL;
		}
		info.type = wcn_rom_patches[i].type;
		strscpy(info.patchName, wcn_rom_patches[i].name, sizeof(info.patchName));
		/* WMT_IOCTL_SET_ROM_PATCH_INFO (copies the record) */
		wmt_lib_set_rom_patch_info(&info, info.type);
	}
	return 0;
}

static int wcn_launcher_thread(void *unused)
{
	P_OSAL_EVENT ev = wmt_lib_get_cmd_event();

	while (!kthread_should_stop()) {
		PUINT8 cmd;
		INT32 ret;

		ret = wait_event_interruptible(ev->waitQueue,
					       kthread_should_stop() ||
					       wmt_lib_get_cmd_status() == MTK_WCN_BOOL_TRUE);
		if (kthread_should_stop())
			break;
		if (ret < 0)
			continue;

		cmd = wmt_lib_get_cmd();	/* takes the command, as WMT_read() does */
		if (!cmd)
			continue;
		if (!strcmp(cmd, "srh_patch")) {
			ret = wcn_srh_patch();
		} else if (!strcmp(cmd, "srh_rom_patch")) {
			ret = wcn_srh_rom_patch();
		} else {
			pr_warn("wcn-launcher: unsupported request '%s'\n", cmd);
			ret = -EINVAL;
		}
		/* as WMT_write(): "ok" -> 0, anything else -> -1 */
		wmt_lib_trigger_cmd_signal(ret ? -1 : 0);
	}
	return 0;
}

INT32 wcn_launcher_start(VOID)
{
	UINT32 chipid;
	INT32 ret;

	/*
	 * COMBO_IOCTL_CONNSYS_SOC_HW_INIT: registers the consys platform
	 * driver (DT probe: registers, IRQs, regulators, clocks, EMI). The
	 * CONSYS itself stays off until a function (Wi-Fi/BT) is switched on.
	 */
	ret = wmt_plat_consys_hw_init();
	if (ret) {
		pr_err("wcn-launcher: consys hw init failed %d\n", ret);
		return ret;
	}

	/* wmt_loader: COMBO_IOCTL_GET_SOC_CHIP_ID + COMBO_IOCTL_SET_CHIP_ID */
	chipid = wmt_plat_get_soc_chipid();
	pr_info("wcn-launcher: SoC chip id 0x%x\n", chipid);
	mtk_wcn_wmt_set_chipid(chipid);
	wmt_detect_set_chip_type(chipid);

	/* wmt_loader: COMBO_IOCTL_DO_MODULE_INIT (kernel-object mode) */
	ret = mtk_wcn_common_drv_init();
	if (ret) {
		pr_err("wcn-launcher: common driver init failed %d\n", ret);
		return ret;
	}

	wcn_launcher_task = kthread_run(wcn_launcher_thread, NULL, "wcn_launcher");
	if (IS_ERR(wcn_launcher_task)) {
		ret = PTR_ERR(wcn_launcher_task);
		wcn_launcher_task = NULL;
		pr_err("wcn-launcher: thread failed %d\n", ret);
		return ret;
	}

	/* wmt_launcher: WMT_IOCTL_SET_STP_MODE */
	return wcn_set_stp_mode((WMT_FM_COMM << 4) | STP_BTIF_FULL);
}

VOID wcn_launcher_stop(VOID)
{
	if (wcn_launcher_task) {
		kthread_stop(wcn_launcher_task);
		wcn_launcher_task = NULL;
	}
	kfree(wcn_patch_info);
	wcn_patch_info = NULL;
}
