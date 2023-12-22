// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {BullLPVault} from "./BullLPVault.sol";

contract DpxEthBullVault is BullLPVault {
    constructor(
        address _lpToken,
        address _storageAddress,
        uint256 _riskPercentage,
        uint256 _feePercentage,
        address _feeReceiver,
        address _oneInchRouter,
        uint256 _vaultCap,
        address _DPXETHFarm
    )
        BullLPVault(
            _lpToken, // Dpx-Eth LP Token
            _storageAddress, // Storage address
            "JonesDpxEthBullVault",
            _riskPercentage, // Risk percentage (1e12 = 100%)
            _feePercentage, // Fee percentage (1e12 = 100%)
            _feeReceiver, // Fee receiver
            payable(_oneInchRouter), // 1Inch router
            _vaultCap, // Cap
            _DPXETHFarm // Dpx-Eth Farm
        )
    {}
}

