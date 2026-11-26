// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2021 MediaTek Inc.
 *               Chun-Jie Chen <chun-jie.chen@mediatek.com>
 * Copyright (c) 2023 Collabora Ltd.
 *               AngeloGioacchino Del Regno <angelogioacchino.delregno@collabora.com>
 */

#include <dt-bindings/clock/mt8192-clk.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include "clk-fhctl.h"
#include "clk-gate.h"
#include "clk-mtk.h"
#include "clk-pll.h"
#include "clk-pllfh.h"

static const struct mtk_gate_regs apmixed_cg_regs = {
	.set_ofs = 0x14,
	.clr_ofs = 0x14,
	.sta_ofs = 0x14,
};

#define GATE_APMIXED(_id, _name, _parent, _shift)	\
	GATE_MTK(_id, _name, _parent, &apmixed_cg_regs, _shift, &mtk_clk_gate_ops_no_setclr_inv)

static const struct mtk_gate apmixed_clks[] = {
	GATE_APMIXED(CLK_APMIXED_MIPID26M, "mipid26m", "clk26m", 16),
};

#define MT8192_PLL_FMAX		(3800UL * MHZ)
#define MT8192_PLL_FMIN		(1500UL * MHZ)
#define MT8192_INTEGER_BITS	8

#define PLL(_id, _name, _reg, _pwr_reg, _en_mask, _flags,		\
			_rst_bar_mask, _pcwbits, _pd_reg, _pd_shift,	\
			_tuner_reg, _tuner_en_reg, _tuner_en_bit,	\
			_pcw_reg, _pcw_shift, _pcw_chg_reg,		\
			_en_reg, _pll_en_bit) {				\
		.id = _id,						\
		.name = _name,						\
		.reg = _reg,						\
		.pwr_reg = _pwr_reg,					\
		.en_mask = _en_mask,					\
		.flags = _flags,					\
		.rst_bar_mask = _rst_bar_mask,				\
		.fmax = MT8192_PLL_FMAX,				\
		.fmin = MT8192_PLL_FMIN,				\
		.pcwbits = _pcwbits,					\
		.pcwibits = MT8192_INTEGER_BITS,			\
		.pd_reg = _pd_reg,					\
		.pd_shift = _pd_shift,					\
		.tuner_reg = _tuner_reg,				\
		.tuner_en_reg = _tuner_en_reg,				\
		.tuner_en_bit = _tuner_en_bit,				\
		.pcw_reg = _pcw_reg,					\
		.pcw_shift = _pcw_shift,				\
		.pcw_chg_reg = _pcw_chg_reg,				\
		.en_reg = _en_reg,					\
		.pll_en_bit = _pll_en_bit,				\
	}

#define PLL_B(_id, _name, _reg, _pwr_reg, _en_mask, _flags,		\
			_rst_bar_mask, _pcwbits, _pd_reg, _pd_shift,	\
			_tuner_reg, _tuner_en_reg, _tuner_en_bit,	\
			_pcw_reg, _pcw_shift)				\
		PLL(_id, _name, _reg, _pwr_reg, _en_mask, _flags,	\
			_rst_bar_mask, _pcwbits, _pd_reg, _pd_shift,	\
			_tuner_reg, _tuner_en_reg, _tuner_en_bit,	\
			_pcw_reg, _pcw_shift, 0, 0, 0)

static const struct mtk_pll_data plls[] = {
	PLL_B(CLK_APMIXED_MAINPLL, "mainpll", 0x0340, 0x034c, 0xff000000,
	      HAVE_RST_BAR, BIT(23), 22, 0x0344, 24, 0, 0, 0, 0x0344, 0),
	PLL_B(CLK_APMIXED_UNIVPLL, "univpll", 0x0308, 0x0314, 0xff000000,
	      HAVE_RST_BAR, BIT(23), 22, 0x030c, 24, 0, 0, 0, 0x030c, 0),
	PLL(CLK_APMIXED_USBPLL, "usbpll", 0x03c4, 0x03cc, 0x00000000,
	    0, 0, 22, 0x03c4, 24, 0, 0, 0, 0x03c4, 0, 0x03c4, 0x03cc, 2),
	PLL_B(CLK_APMIXED_MSDCPLL, "msdcpll", 0x0350, 0x035c, 0x00000000,
	      0, 0, 22, 0x0354, 24, 0, 0, 0, 0x0354, 0),
	PLL_B(CLK_APMIXED_MMPLL, "mmpll", 0x0360, 0x036c, 0xff000000,
	      HAVE_RST_BAR, BIT(23), 22, 0x0364, 24, 0, 0, 0, 0x0364, 0),
	PLL_B(CLK_APMIXED_ADSPPLL, "adsppll", 0x0370, 0x037c, 0xff000000,
	      HAVE_RST_BAR, BIT(23), 22, 0x0374, 24, 0, 0, 0, 0x0374, 0),
	PLL_B(CLK_APMIXED_MFGPLL, "mfgpll", 0x0268, 0x0274, 0x00000000,
	      0, 0, 22, 0x026c, 24, 0, 0, 0, 0x026c, 0),
	PLL_B(CLK_APMIXED_TVDPLL, "tvdpll", 0x0380, 0x038c, 0x00000000,
	      0, 0, 22, 0x0384, 24, 0, 0, 0, 0x0384, 0),
	PLL_B(CLK_APMIXED_APLL1, "apll1", 0x0318, 0x0328, 0x00000000,
	      0, 0, 32, 0x031c, 24, 0x0040, 0x000c, 0, 0x0320, 0),
	PLL_B(CLK_APMIXED_APLL2, "apll2", 0x032c, 0x033c, 0x00000000,
	      0, 0, 32, 0x0330, 24, 0, 0, 0, 0x0334, 0),
};

/*
 * MT6873 (Dimensity 800): same apmixedsys, but the CPU PLLs belong to Linux
 * (MT8192 hands them to the MCUPM, cpufreq-hw). ARMPLL_LL feeds the A55
 * cluster, ARMPLL_BL0 the A76 cluster, CCIPLL the CCI; the other BL PLLs are
 * not used. Always on (PLL_AO): only the rate changes. The post dividers
 * follow the vendor MT6873 DVFS tables, which do not fit a single fmin
 * (ARMPLL_LL runs 756 MHz at /2 but 1541 MHz at /2 as well).
 */
#define MT6873_CPU_PLL(_id, _name, _reg, _div_table) {			\
		.id = _id,						\
		.name = _name,						\
		.reg = _reg,						\
		.pwr_reg = _reg + 0xc,					\
		.flags = PLL_AO,					\
		.fmax = MT8192_PLL_FMAX,				\
		.pcwbits = 22,						\
		.pcwibits = MT8192_INTEGER_BITS,			\
		.pd_reg = _reg + 0x4,					\
		.pd_shift = 24,						\
		.pcw_reg = _reg + 0x4,					\
		.pcw_shift = 0,						\
		.div_table = _div_table,				\
	}

/* { post divider exponent, highest rate for it }, highest rate first */
static const struct mtk_pll_div_table mt6873_armpll_ll_div[] = {
	{ .div = 0, .freq = 2000000000 },
	{ .div = 1, .freq = 1541000000 },
	{ .div = 2, .freq = 650000000 },
	{ /* sentinel */ }
};

static const struct mtk_pll_div_table mt6873_armpll_bl_div[] = {
	{ .div = 0, .freq = 2000000000 },
	{ .div = 1, .freq = 1548000000 },
	{ /* sentinel */ }
};

/* CCIPLL never runs at /1: /2 down to 816 MHz, /4 below */
static const struct mtk_pll_div_table mt6873_ccipll_div[] = {
	{ .div = 0, .freq = 1340000000 },
	{ .div = 1, .freq = 1340000000 },
	{ .div = 2, .freq = 730000000 },
	{ /* sentinel */ }
};

static const struct mtk_pll_data mt6873_plls[] = {
	PLL_B(CLK_APMIXED_MAINPLL, "mainpll", 0x0340, 0x034c, 0xff000000,
	      HAVE_RST_BAR, BIT(23), 22, 0x0344, 24, 0, 0, 0, 0x0344, 0),
	PLL_B(CLK_APMIXED_UNIVPLL, "univpll", 0x0308, 0x0314, 0xff000000,
	      HAVE_RST_BAR, BIT(23), 22, 0x030c, 24, 0, 0, 0, 0x030c, 0),
	PLL(CLK_APMIXED_USBPLL, "usbpll", 0x03c4, 0x03cc, 0x00000000,
	    0, 0, 22, 0x03c4, 24, 0, 0, 0, 0x03c4, 0, 0x03c4, 0x03cc, 2),
	PLL_B(CLK_APMIXED_MSDCPLL, "msdcpll", 0x0350, 0x035c, 0x00000000,
	      0, 0, 22, 0x0354, 24, 0, 0, 0, 0x0354, 0),
	PLL_B(CLK_APMIXED_MMPLL, "mmpll", 0x0360, 0x036c, 0xff000000,
	      HAVE_RST_BAR, BIT(23), 22, 0x0364, 24, 0, 0, 0, 0x0364, 0),
	PLL_B(CLK_APMIXED_ADSPPLL, "adsppll", 0x0370, 0x037c, 0xff000000,
	      HAVE_RST_BAR, BIT(23), 22, 0x0374, 24, 0, 0, 0, 0x0374, 0),
	PLL_B(CLK_APMIXED_MFGPLL, "mfgpll", 0x0268, 0x0274, 0x00000000,
	      0, 0, 22, 0x026c, 24, 0, 0, 0, 0x026c, 0),
	PLL_B(CLK_APMIXED_TVDPLL, "tvdpll", 0x0380, 0x038c, 0x00000000,
	      0, 0, 22, 0x0384, 24, 0, 0, 0, 0x0384, 0),
	PLL_B(CLK_APMIXED_APLL1, "apll1", 0x0318, 0x0328, 0x00000000,
	      0, 0, 32, 0x031c, 24, 0x0040, 0x000c, 0, 0x0320, 0),
	PLL_B(CLK_APMIXED_APLL2, "apll2", 0x032c, 0x033c, 0x00000000,
	      0, 0, 32, 0x0330, 24, 0, 0, 0, 0x0334, 0),
	MT6873_CPU_PLL(CLK_APMIXED_ARMPLL_LL, "armpll_ll", 0x0208,
		       mt6873_armpll_ll_div),
	MT6873_CPU_PLL(CLK_APMIXED_ARMPLL_BL, "armpll_bl", 0x0218,
		       mt6873_armpll_bl_div),
	MT6873_CPU_PLL(CLK_APMIXED_CCIPLL, "ccipll", 0x0258,
		       mt6873_ccipll_div),
};

struct mt8192_apmixed_data {
	const struct mtk_pll_data *plls;
	unsigned int num_plls;
};

static const struct mt8192_apmixed_data mt8192_apmixed_data = {
	.plls = plls,
	.num_plls = ARRAY_SIZE(plls),
};

static const struct mt8192_apmixed_data mt6873_apmixed_data = {
	.plls = mt6873_plls,
	.num_plls = ARRAY_SIZE(mt6873_plls),
};

enum fh_pll_id {
	FH_ARMPLL_LL,
	FH_ARMPLL_BL0,
	FH_ARMPLL_BL1,
	FH_ARMPLL_BL2,
	FH_ARMPLL_BL3,
	FH_CCIPLL,
	FH_MFGPLL,
	FH_MEMPLL,
	FH_MPLL,
	FH_MMPLL,
	FH_MAINPLL,
	FH_MSDCPLL,
	FH_ADSPPLL,
	FH_APUPLL,
	FH_TVDPLL,
	FH_NR_FH,
};

#define FH(_pllid, _fhid, _offset) {					\
		.data = {						\
			.pll_id = _pllid,				\
			.fh_id = _fhid,					\
			.fh_ver = FHCTL_PLLFH_V2,			\
			.fhx_offset = _offset,				\
			.dds_mask = GENMASK(21, 0),			\
			.slope0_value = 0x6003c97,			\
			.slope1_value = 0x6003c97,			\
			.sfstrx_en = BIT(2),				\
			.frddsx_en = BIT(1),				\
			.fhctlx_en = BIT(0),				\
			.tgl_org = BIT(31),				\
			.dvfs_tri = BIT(31),				\
			.pcwchg = BIT(31),				\
			.dt_val = 0x0,					\
			.df_val = 0x9,					\
			.updnlmt_shft = 16,				\
			.msk_frddsx_dys = GENMASK(23, 20),		\
			.msk_frddsx_dts = GENMASK(19, 16),		\
		},							\
	}

static struct mtk_pllfh_data pllfhs[] = {
	FH(CLK_APMIXED_MFGPLL, FH_MFGPLL, 0xb4),
	FH(CLK_APMIXED_MMPLL, FH_MMPLL, 0xf0),
	FH(CLK_APMIXED_MAINPLL, FH_MAINPLL, 0x104),
	FH(CLK_APMIXED_MSDCPLL, FH_MSDCPLL, 0x118),
	FH(CLK_APMIXED_ADSPPLL, FH_ADSPPLL, 0x12c),
	FH(CLK_APMIXED_TVDPLL, FH_TVDPLL, 0x154),
};

static const struct of_device_id of_match_clk_mt8192_apmixed[] = {
	{ .compatible = "mediatek,mt6873-apmixedsys", .data = &mt6873_apmixed_data },
	{ .compatible = "mediatek,mt8192-apmixedsys", .data = &mt8192_apmixed_data },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, of_match_clk_mt8192_apmixed);

static int clk_mt8192_apmixed_probe(struct platform_device *pdev)
{
	struct clk_hw_onecell_data *clk_data;
	struct device_node *node = pdev->dev.of_node;
	const u8 *fhctl_node = "mediatek,mt8192-fhctl";
	const struct mt8192_apmixed_data *data = of_device_get_match_data(&pdev->dev);
	int r;

	clk_data = mtk_alloc_clk_data(CLK_APMIXED_NR_CLK);
	if (!clk_data)
		return -ENOMEM;

	fhctl_parse_dt(fhctl_node, pllfhs, ARRAY_SIZE(pllfhs));

	r = mtk_clk_register_pllfhs(&pdev->dev, data->plls, data->num_plls,
				    pllfhs, ARRAY_SIZE(pllfhs), clk_data);
	if (r)
		goto free_clk_data;

	r = mtk_clk_register_gates(&pdev->dev, node, apmixed_clks,
				   ARRAY_SIZE(apmixed_clks), clk_data);
	if (r)
		goto unregister_plls;

	r = of_clk_add_hw_provider(node, of_clk_hw_onecell_get, clk_data);
	if (r)
		goto unregister_gates;

	return r;

unregister_gates:
	mtk_clk_unregister_gates(apmixed_clks, ARRAY_SIZE(apmixed_clks), clk_data);
unregister_plls:
	mtk_clk_unregister_pllfhs(data->plls, data->num_plls, pllfhs,
				  ARRAY_SIZE(pllfhs), clk_data);
free_clk_data:
	mtk_free_clk_data(clk_data);
	return r;
}

static void clk_mt8192_apmixed_remove(struct platform_device *pdev)
{
	struct device_node *node = pdev->dev.of_node;
	struct clk_hw_onecell_data *clk_data = platform_get_drvdata(pdev);
	const struct mt8192_apmixed_data *data = of_device_get_match_data(&pdev->dev);

	of_clk_del_provider(node);
	mtk_clk_unregister_gates(apmixed_clks, ARRAY_SIZE(apmixed_clks), clk_data);
	mtk_clk_unregister_pllfhs(data->plls, data->num_plls, pllfhs,
				  ARRAY_SIZE(pllfhs), clk_data);
	mtk_free_clk_data(clk_data);
}

static struct platform_driver clk_mt8192_apmixed_drv = {
	.driver = {
		.name = "clk-mt8192-apmixed",
		.of_match_table = of_match_clk_mt8192_apmixed,
	},
	.probe = clk_mt8192_apmixed_probe,
	.remove = clk_mt8192_apmixed_remove,
};
module_platform_driver(clk_mt8192_apmixed_drv);
MODULE_DESCRIPTION("MediaTek MT8192 apmixed clocks driver");
MODULE_LICENSE("GPL");
