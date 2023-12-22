// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

interface IPriceConsumer2 {

    /**
     * Network: Arbitrum One
     * ETH/USD (Base_0): 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612
     * GBP/USD (quote_1): 0x9C4424Fd84C6661F97D8d6b3fc3C1aAc2BeDd137
     * EUR/USD (quote_2): 0xA14d53bC1F1c0F31B4aA3BD109344E5009051a84
     * JPY/USD (quote_3): 0x3dD6e51CB9caE717d5a8778CF79A04029f9cFDF8
     * KRW/USD (quote_4): 0x85bb02E0Ae286600d1c68Bb6Ce22Cc998d411916
     * CNY/USD (quote_5): 0xcC3370Bde6AFE51e1205a5038947b9836371eCCb
     * AUD/USD (quote_6): 0x9854e9a850e7C354c1de177eA953a6b1fba8Fc22
     * CAD/USD (quote_7): 0xf6DA27749484843c4F02f5Ad1378ceE723dD61d4
     * CHF/USD (quote_8): 0xe32AccC8c4eC03F6E75bd3621BfC9Fbb234E1FC3
     * ARS/USD (quote_9): 0x0000000000000000000000000000000000000000
     * PHP/USD (quote_10): 0xfF82AAF635645fD0bcc7b619C3F28004cDb58574
     * NZD/USD (quote_11): 0x0000000000000000000000000000000000000000
     * SGD/USD (quote_12): 0xF0d38324d1F86a176aC727A4b0c43c9F9d9c5EB1
     * NGN/USD (quote_13): 0x0000000000000000000000000000000000000000
     * ZAR/USD (quote_14): 0x0000000000000000000000000000000000000000
     * RUB/USD (quote_15): 0x0000000000000000000000000000000000000000
     * INR/USD (quote_16): 0x0000000000000000000000000000000000000000
     * BRL/USD (quote_17): 0x04b7384473A2aDF1903E3a98aCAc5D62ba8C2702
     */

    function getPriceFeed(uint seq) external view returns (address);

    function decimals(address quote) external view returns (uint8);

    function getCentPriceInWei(uint seq) external view returns (uint);

}

