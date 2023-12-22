// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {BearLPVault} from "./BearLPVault.sol";

contract DpxEthBearVault is BearLPVault {
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
        BearLPVault(
            _lpToken, // Dpx-Eth LP Token
            _storageAddress, // Replace with storage address
            "JonesDpxEthBearVault",
            _riskPercentage, // Risk percentage (1e12 = 100%)
            _feePercentage, // Fee percentage (1e12 = 100%)
            _feeReceiver, // Fee receiver
            payable(_oneInchRouter), // 1Inch router
            _vaultCap, // Cap
            _DPXETHFarm // Dpx-Eth Farm
        )
    {}
}

