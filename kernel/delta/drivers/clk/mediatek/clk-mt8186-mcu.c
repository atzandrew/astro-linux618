// SPDX-License-Identifier: GPL-2.0-only
//
// Copyright (c) 2022 MediaTek Inc.
// Author: Chun-Jie Chen <chun-jie.chen@mediatek.com>

#include <linux/clk-provider.h>
#include <linux/platform_device.h>
#include <dt-bindings/clock/mt8186-clk.h>

#include "clk-mtk.h"

static const char * const mcu_armpll_ll_parents[] = {
	"clk26m",
	"armpll_ll",
	"mainpll",
	"univpll_d2"
};

static const char * const mcu_armpll_bl_parents[] = {
	"clk26m",
	"armpll_bl",
	"mainpll",
	"univpll_d2"
};

static const char * const mcu_armpll_bus_parents[] = {
	"clk26m",
	"ccipll",
	"mainpll",
	"univpll_d2"
};

/*
 * We only configure the CPU muxes when adjust CPU frequency in MediaTek CPUFreq Driver.
 * Other fields like divider always keep the same value. (set once in bootloader)
 */
static struct mtk_composite mcu_muxes[] = {
	/* CPU_PLLDIV_CFG0 */
	MUX(CLK_MCU_ARMPLL_LL_SEL, "mcu_armpll_ll_sel", mcu_armpll_ll_parents, 0x2A0, 9, 2),
	/* CPU_PLLDIV_CFG1 */
	MUX(CLK_MCU_ARMPLL_BL_SEL, "mcu_armpll_bl_sel", mcu_armpll_bl_parents, 0x2A4, 9, 2),
	/* BUS_PLLDIV_CFG */
	MUX(CLK_MCU_ARMPLL_BUS_SEL, "mcu_armpll_bus_sel", mcu_armpll_bus_parents, 0x2E0, 9, 2),
};

static const struct mtk_clk_desc mcu_desc = {
	.composite_clks = mcu_muxes,
	.num_composite_clks = ARRAY_SIZE(mcu_muxes),
};

/*
 * MT6873: same CPU_PLLDIV_CFG0/1 and BUS_PLLDIV_CFG muxes (vendor MT6873
 * DVFS: MP0/MP1/BUS_PLL_DIVIDER, mux 0 = 26 MHz, 1 = ARMPLL, 2 = MAINPLL,
 * 3 = UNIVPLL). The CKDIV1 dividers in bits 21:17 stay at /1 (the vendor
 * tables never use another value). Clock IDs: dt-bindings mt8192-clk.h
 * MCUSYS, same numbers as here.
 */
static const char * const mt6873_mcu_armpll_ll_parents[] = {
	"clk26m",
	"armpll_ll",
	"mainpll",
	"univpll"
};

static const char * const mt6873_mcu_armpll_bl_parents[] = {
	"clk26m",
	"armpll_bl",
	"mainpll",
	"univpll"
};

static const char * const mt6873_mcu_armpll_bus_parents[] = {
	"clk26m",
	"ccipll",
	"mainpll",
	"univpll"
};

static struct mtk_composite mt6873_mcu_muxes[] = {
	MUX(CLK_MCU_ARMPLL_LL_SEL, "mcu_armpll_ll_sel", mt6873_mcu_armpll_ll_parents, 0x2A0, 9, 2),
	MUX(CLK_MCU_ARMPLL_BL_SEL, "mcu_armpll_bl_sel", mt6873_mcu_armpll_bl_parents, 0x2A4, 9, 2),
	MUX(CLK_MCU_ARMPLL_BUS_SEL, "mcu_armpll_bus_sel", mt6873_mcu_armpll_bus_parents, 0x2E0, 9, 2),
};

static const struct mtk_clk_desc mt6873_mcu_desc = {
	.composite_clks = mt6873_mcu_muxes,
	.num_composite_clks = ARRAY_SIZE(mt6873_mcu_muxes),
};

static const struct of_device_id of_match_clk_mt8186_mcu[] = {
	{ .compatible = "mediatek,mt6873-mcusys", .data = &mt6873_mcu_desc },
	{ .compatible = "mediatek,mt8186-mcusys", .data = &mcu_desc },
	{ /* sentinel */}
};
MODULE_DEVICE_TABLE(of, of_match_clk_mt8186_mcu);

static struct platform_driver clk_mt8186_mcu_drv = {
	.driver = {
		.name = "clk-mt8186-mcu",
		.of_match_table = of_match_clk_mt8186_mcu,
	},
	.probe = mtk_clk_simple_probe,
	.remove = mtk_clk_simple_remove,
};
module_platform_driver(clk_mt8186_mcu_drv);

MODULE_DESCRIPTION("MediaTek MT8186 mcusys clocks driver");
MODULE_LICENSE("GPL");
