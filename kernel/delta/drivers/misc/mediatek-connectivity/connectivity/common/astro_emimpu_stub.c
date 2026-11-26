// SPDX-License-Identifier: GPL-2.0
/*
 * Astro Slide (MT6873): EMI MPU API used by the CONSYS platform file.
 *
 * Mainline has no MediaTek EMI MPU driver. The stock kernel programs the
 * CONN region (AP + CONN domains: no protection) through TF-A
 * (MTK_SIP_EMIMPU_CONTROL). These stubs only log; the zinwa-q25-linux
 * MT6789 port makes no EMI MPU call at all and its CONSYS runs. If the
 * CONN MCU faults on its EMI window on the Astro, replace this with the
 * SMC (docs/wifi-stock.md, open questions).
 */
#include <linux/module.h>
#include <linux/printk.h>
#include <soc/mediatek/emi.h>

int mtk_emimpu_init_region(struct emimpu_region_t *rg_info, unsigned int rg_num)
{
	pr_info("astro-emimpu: region %u: no EMI MPU driver, not programmed\n",
		rg_num);
	return 0;
}
EXPORT_SYMBOL(mtk_emimpu_init_region);

int mtk_emimpu_set_addr(struct emimpu_region_t *rg_info,
			unsigned long long start, unsigned long long end)
{
	pr_info("astro-emimpu: would cover 0x%llx-0x%llx\n", start, end);
	return 0;
}
EXPORT_SYMBOL(mtk_emimpu_set_addr);

int mtk_emimpu_set_apc(struct emimpu_region_t *rg_info,
		       unsigned int d_num, unsigned int apc)
{
	return 0;
}
EXPORT_SYMBOL(mtk_emimpu_set_apc);

int mtk_emimpu_set_protection(struct emimpu_region_t *rg_info)
{
	return 0;
}
EXPORT_SYMBOL(mtk_emimpu_set_protection);

int mtk_emimpu_free_region(struct emimpu_region_t *rg_info)
{
	return 0;
}
EXPORT_SYMBOL(mtk_emimpu_free_region);
