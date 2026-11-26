// SPDX-License-Identifier: GPL-2.0
/*
 * Power-off for the MediaTek MT6359(P) PMIC (Planet Astro Slide, MT6873).
 *
 * The vendor ATF does not power the board off on PSCI SYSTEM_OFF. The
 * vendor 4.14 kernel for MT6873 (k6873v1_64_defconfig: CONFIG_MFD_MT6358,
 * CONFIG_RTC_DRV_MT6358) powers off in drivers/mfd/mt6358-core.c
 * mt6358_power_off(): one write, RG_PWRHOLD (PPCCTL0 0xa08 bit 0) = 0,
 * which releases the PMIC power hold. Its RTC driver's shutdown hook
 * only re-arms a pending power-on alarm (none here); there is no RTC
 * BBPU sequence on this platform (unlike MT6771/MT6358).
 *
 * With a charger or USB present the PMIC stays up. Then, after ~1.1 s,
 * this driver resets through TOPRGU as the vendor arch_reset(0,
 * "charger") does on wdt_v2 (mtk_wdt_v2.c wdt_arch_reset()): the
 * "bypass power key" flag (NONRST_REG2 bit 13) cleared, so the bootloader
 * decides (power-off charging, or power-off).
 */

#include <linux/delay.h>
#include <linux/io.h>
#include <linux/mfd/mt6397/core.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/platform_device.h>
#include <linux/reboot.h>
#include <linux/regmap.h>

/* MT6359P (vendor include/linux/mfd/mt6359p/registers.h) */
#define MT6359_PPCCTL0			0xa08
#define  MT6359_RG_PWRHOLD		BIT(0)

/* TOPRGU, wdt_v2 (vendor drivers/watchdog/mediatek/wdt/common/wdt_v2) */
#define WDT_MODE			0x00
#define  WDT_MODE_EXTEN			BIT(2)
#define  WDT_MODE_IRQ			BIT(3)
#define  WDT_MODE_DUAL_MODE		BIT(6)
#define  WDT_MODE_KEY			0x22000000
#define WDT_RESTART			0x08
#define  WDT_RESTART_KEY		0x1971
#define WDT_SWRST			0x14
#define  WDT_SWRST_KEY			0x1209
#define WDT_NONRST_REG2			0x24
#define  WDT_NONRST2_BYPASS_PWR_KEY	BIT(13)

struct mt6359_pwrc {
	struct device *dev;
	struct regmap *map;
	void __iomem *toprgu;
};

/* vendor wdt_arch_reset() without WD_SW_RESET_BYPASS_PWR_KEY */
static void mt6359_pwrc_wdt_reset(struct mt6359_pwrc *p)
{
	u32 mode, nonrst2;

	writel(WDT_RESTART_KEY, p->toprgu + WDT_RESTART);

	nonrst2 = readl(p->toprgu + WDT_NONRST_REG2);
	nonrst2 &= ~WDT_NONRST2_BYPASS_PWR_KEY;

	mode = readl(p->toprgu + WDT_MODE);
	mode &= ~(WDT_MODE_IRQ | WDT_MODE_DUAL_MODE);
	mode |= WDT_MODE_KEY | WDT_MODE_EXTEN;

	writel(nonrst2, p->toprgu + WDT_NONRST_REG2);
	writel(mode, p->toprgu + WDT_MODE);

	udelay(100);
	writel(WDT_SWRST_KEY, p->toprgu + WDT_SWRST);
	mdelay(1000);
}

static int mt6359_pwrc_power_off(struct sys_off_data *data)
{
	struct mt6359_pwrc *p = data->cb_data;
	int ret, i;

	/* vendor mt6358_power_off() */
	ret = regmap_update_bits(p->map, MT6359_PPCCTL0, MT6359_RG_PWRHOLD, 0);
	if (ret)
		dev_emerg(p->dev, "RG_PWRHOLD write failed: %d\n", ret);

	/* vendor mt_power_off(): up to 11 x 100 ms for the cut */
	for (i = 0; i < 11; i++)
		mdelay(100);

	if (!p->toprgu) {
		dev_emerg(p->dev, "still powered, no TOPRGU for the fallback\n");
		return NOTIFY_DONE;
	}

	dev_emerg(p->dev, "still powered: reset without bypass power key\n");
	mt6359_pwrc_wdt_reset(p);

	/* reset did not happen: let the kernel's own path continue */
	return NOTIFY_DONE;
}

static int mt6359_pwrc_probe(struct platform_device *pdev)
{
	struct mt6397_chip *chip = dev_get_drvdata(pdev->dev.parent);
	struct device *dev = &pdev->dev;
	struct device_node *np;
	struct mt6359_pwrc *p;
	unsigned int val;
	int ret;

	/* opt-in: only with a DT node (status = "okay") */
	if (!dev->of_node)
		return -ENODEV;

	if (!chip || chip->chip_id != MT6359_CHIP_ID)
		return dev_err_probe(dev, -ENODEV, "not an MT6359\n");

	p = devm_kzalloc(dev, sizeof(*p), GFP_KERNEL);
	if (!p)
		return -ENOMEM;

	p->dev = dev;
	p->map = chip->regmap;

	/* TOPRGU is owned by mtk_wdt: map it without requesting the region */
	np = of_parse_phandle(dev->of_node, "mediatek,toprgu", 0);
	if (np) {
		p->toprgu = of_iomap(np, 0);
		of_node_put(np);
	}
	if (!p->toprgu)
		dev_warn(dev, "no TOPRGU: no fallback reset\n");

	ret = devm_register_sys_off_handler(dev, SYS_OFF_MODE_POWER_OFF,
					    SYS_OFF_PRIO_HIGH,
					    mt6359_pwrc_power_off, p);
	if (ret)
		return dev_err_probe(dev, ret, "power-off handler\n");

	ret = regmap_read(p->map, MT6359_PPCCTL0, &val);
	dev_info(dev, "power-off ready (PPCCTL0 %s0x%x, TOPRGU %s)\n",
		 ret ? "unreadable " : "", ret ? 0 : val,
		 p->toprgu ? "mapped" : "none");
	return 0;
}

static const struct of_device_id mt6359_pwrc_dt_match[] = {
	{ .compatible = "mediatek,mt6359-pwrc" },
	{ }
};
MODULE_DEVICE_TABLE(of, mt6359_pwrc_dt_match);

static struct platform_driver mt6359_pwrc_driver = {
	.probe = mt6359_pwrc_probe,
	.driver = {
		.name = "mt6359-pwrc",
		.of_match_table = mt6359_pwrc_dt_match,
	},
};
module_platform_driver(mt6359_pwrc_driver);

MODULE_DESCRIPTION("MediaTek MT6359 PMIC power-off");
MODULE_LICENSE("GPL");
