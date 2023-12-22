// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./AclPriceFeedAggregatorBASE.sol";



contract AclPriceFeedAggregatorArbitrum is AclPriceFeedAggregatorBASE {
    
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    constructor() {
        tokenMap[ETH] = WETH;   //nativeToken to wrappedToken
        tokenMap[address(0)] = WETH;

        priceFeedAggregator[address(0)] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
        priceFeedAggregator[ETH] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;// ETH
        priceFeedAggregator[WETH] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;// WETH
        priceFeedAggregator[0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f] = 0xd0C7101eACbB49F3deCcCc166d238410D6D46d57;// WBTC
        priceFeedAggregator[0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;// USDC
        priceFeedAggregator[0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9] = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;// USDT
        priceFeedAggregator[0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0] = 0x9C917083fDb403ab5ADbEC26Ee294f6EcAda2720;// UNI
        priceFeedAggregator[0xf97f4df75117a78c1A5a0DBb814Af92458539FB4] = 0x86E53CF1B870786351Da77A57575e79CB55812CB;// LINK
        priceFeedAggregator[0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F] = 0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8;// FRAX
        priceFeedAggregator[0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1] = 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;// DAI
        priceFeedAggregator[0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978] = 0xaebDA2c976cfd1eE1977Eac079B4382acb849325;// CRV
        priceFeedAggregator[0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60] = address(0);// LDO
        priceFeedAggregator[0x6694340fc020c5E6B96567843da2df01b2CE1eb6] = address(0);// STG
        priceFeedAggregator[0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a] = 0xDB98056FecFff59D032aB628337A4887110df3dB;// GMX
        priceFeedAggregator[0x539bdE0d7Dbd336b79148AA742883198BBF60342] = 0x47E55cCec6582838E173f252D08Afd8116c2202d;// MAGIC
        priceFeedAggregator[0x5979D7b546E38E414F7E9822514be443A4800529] = address(0);// wstETH
    }
}
