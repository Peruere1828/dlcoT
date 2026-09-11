## lab03 拓展版 电子时钟 pin map (Nexys A7-100T)
## SW[1:0] 模式: 00 时钟 / 01 校时 / 10 闹铃设置 / 11 秒表
## SW[3:2] 字段: 00 秒 / 01 分 / 10 时 (校时、闹铃设置用)
## SW4 闹铃开关 ; BTNC = +1/开始暂停 ; BTNL = 秒表清零
## 注意: 本设计不使用 SW5(T18), 该开关已损坏

## 100MHz 系统时钟
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK100MHZ }];
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## 拨码开关
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { SW[0] }];   # 模式位0
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { SW[1] }];   # 模式位1
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { SW_F[0] }]; # 字段位0
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { SW_F[1] }]; # 字段位1
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { SW_AL }];   # 闹铃开关

## 按键
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { BTNC }]; # 开始/暂停/+1
set_property -dict { PACKAGE_PIN P17   IOSTANDARD LVCMOS33 } [get_ports { BTNL }]; # 秒表清零

## LED: LED0 闹铃闪烁, LED1 闹铃使能, LED[3:2] 当前模式
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { LED[0] }]; # led0
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { LED[1] }]; # led1
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { LED[2] }]; # led2
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { LED[3] }]; # led3

## 数码管位选 (AN5:AN0 显示, AN7:6 熄灭)
set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { AN[0] }]; # an[0]
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { AN[1] }]; # an[1]
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { AN[2] }]; # an[2]
set_property -dict { PACKAGE_PIN J14   IOSTANDARD LVCMOS33 } [get_ports { AN[3] }]; # an[3]
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { AN[4] }]; # an[4]
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { AN[5] }]; # an[5]
set_property -dict { PACKAGE_PIN K2    IOSTANDARD LVCMOS33 } [get_ports { AN[6] }]; # an[6]
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { AN[7] }]; # an[7]

## 段码 HEX[7:0] = {dp, seg[6:0]}
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { HEX[7] }]; # cg
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { HEX[6] }]; # cf
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { HEX[5] }]; # ce
set_property -dict { PACKAGE_PIN K13   IOSTANDARD LVCMOS33 } [get_ports { HEX[4] }]; # cd
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { HEX[3] }]; # cc
set_property -dict { PACKAGE_PIN R10   IOSTANDARD LVCMOS33 } [get_ports { HEX[2] }]; # cb
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { HEX[1] }]; # ca
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { HEX[0] }]; # dp