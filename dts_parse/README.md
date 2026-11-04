# Device Tree Parsing Tool
 
## Purpose
 
- This tool shows all the files included by a single `.dts` file. This is helpful when many include files include other include files, and it becomes difficult to follow.
- For each included file, it also shows which nodes are set in that file. For example, if you are looking for examples of how the i2c channels are configured, you can quickly find all the `.dtsi` files that set them.
## Usage
 
```sh
chmod +x dts_parse.sh
./dts_parse.sh <path_to_dts_file>
```

## Example usage
```
./dts_parse.sh arch/arm64/boot/dts/renesasr9a07g054l2-smarc.dts
-----------------------------------
Include order
-----------------------------------

r9a07g054l2-smarc.dts
└─r9a07g054l2.dtsi
  └─r9a07g054.dtsi
└─rzg2l-smarc-som.dtsi
└─rzg2l-smarc-pinfunction.dtsi
└─rz-smarc-common.dtsi
└─rzg2l-smarc.dtsi


-------------------------------------------------------------
Order of how files and nodes are parsed.
-------------------------------------------------------------
Remember, the #include is at the top of the files and the nodes come after. So that means the last file
that gets included will have the nodes that get processed first. This is important to know when you have
multiple files that modify the same node.

r9a07g054.dtsi
  nodes new:
    audio_clk1           audio_clk2           can_clk              extal_clk
    cluster0_opp         cpus                 gpu_opp_table        pmu
    psci                 soc                  thermal-zones        timer
  nodes override:


r9a07g054l2.dtsi
  nodes new:

  nodes override:


rzg2l-smarc-som.dtsi
  nodes new:
    aliases              chosen               memory@48000000      reserved-memory
    mmngr                mmngrbuf             vspm_if              gpio-keys
    reg_1p8v             reg_3p3v             reg_1p1v             vccq_sdhi0
    x2                   phy0                 phy1                 raa215300
    adc_pins             eth0_pins            eth1_pins            gpio-sd0-pwr-en-hog
    qspi0_pins           sd0-dev-sel-hog      sdhi0_emmc_pins      sdhi0_pins
    sdhi0_pins_uhs       flash@0
  nodes override:
    &adc                 &eth0                &eth1                &extal_clk
    &gpu                 &i2c3                &ostm1               &ostm2
    &pinctrl             &sbc                 &sdhi0               &sdhi0
    &wdt0                &wdt1

rzg2l-smarc-pinfunction.dtsi
  nodes new:
    can0_pins            can0-stb-hog         can1_pins            can1-stb-hog
    gpt_pins             i2c0_pins            i2c1_pins            i2c3_pins
    mtu3_pins            scif0_pins           scif2_pins           sd1-pwr-en-hog
    sdhi1_pins           sdhi1_pins_uhs       sound_clk_pins       spi1_pins
    ssi0_pins            ssi1_pins            usb0_pins            usb1_pins
  nodes override:
    &pinctrl

rz-smarc-common.dtsi
  nodes new:
    aliases              chosen               snd_rzg2l            vccq_sdhi1
    x1                   channel0             channel1
  nodes override:
    &audio_clk1          &audio_clk2          &canfd               &ehci0
    &ehci1               &hsusb               &i2c0                &i2c1
    &ohci0               &ohci1               &phyrst              &scif0
    &sdhi1               &spi1                &usb2_phy0           &usb2_phy1

rzg2l-smarc.dtsi
  nodes new:
    aliases              osc1                 hdmi-out             sound_card
    ports                adv7535              wm8978               versa3
    mtu3_ch34            i2s2_port
  nodes override:
    &cpu_dai             &dsi                 &du                  &i2c1
    &gpt                 &i2c3                &mtu3                &sdhi1
    &spi1                &poe3                &poeggd              &scif2
    &ssi0                &ssi1                &vccq_sdhi1

r9a07g054l2-smarc.dts
  nodes new:

  nodes override:
```
 
