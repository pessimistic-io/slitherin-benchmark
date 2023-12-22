// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {BearLPVault} from "./BearLPVault.sol";

contract RdpxEthBearVault is BearLPVault {
    constructor(
        address _lpToken,
        address _storageAddress,
        uint256 _riskPercentage,
        uint256 _feePercentage,
        address _feeReceiver,
        address _oneInchRouter,
        uint256 _vaultCap,
        address _RDPXETHFarm
    )
        BearLPVault(
            _lpToken, // Rdpx-Eth LP Token
            _storageAddress, // Replace with storage address
            "JonesRdpxEthBearVault",
            _riskPercentage, // Risk percentage (1e12 = 100%)
            _feePercentage, // Fee percentage (1e12 = 100%)
            _feeReceiver, // Fee receiver
            payable(_oneInchRouter), // 1Inch router
            _vaultCap, // Cap
            _RDPXETHFarm // Rdpx-Eth Farm
        )
    {}
}

