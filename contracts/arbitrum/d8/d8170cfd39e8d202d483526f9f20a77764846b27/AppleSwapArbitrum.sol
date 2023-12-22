// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "./AppleSwap.sol";

contract AppleSwapArbitrum is AppleSwap {
    constructor(uint256 _teamFee, address _teamWallet) AppleSwap(_teamFee, _teamWallet) {}

    function UNISWAP_V2_ROUTER() internal pure override returns (IUniswapV2Router02) {
        return IUniswapV2Router02(0x8a10a139D2717CE8882d99E5D9FeDA0F6129dD11);
    }

    function UNISWAP_FACTORY() internal pure override returns (IUniswapV2Factory) {
        return IUniswapV2Factory(0x94F8b11339d2630A522Ff6410B7e145DFbE41f79);
    }
}

