// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "./InstantSwapReferrer.sol";

contract InstantSwapArbitrum is InstantSwapReferrer {
    constructor(uint256 _teamFee, address _teamWallet) InstantSwapReferrer(_teamFee, _teamWallet) {}

    function UNISWAP_V2_ROUTER() internal pure override returns (IRouterReferer) {
        return IRouterReferer(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);
    }

    function UNISWAP_FACTORY() internal pure override returns (IUniswapV2Factory) {
        return IUniswapV2Factory(0x6EcCab422D763aC031210895C81787E87B43A652);
    }
}

