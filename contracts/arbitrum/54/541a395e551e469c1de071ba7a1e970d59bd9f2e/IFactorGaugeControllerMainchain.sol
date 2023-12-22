// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./IFactorGaugeController.sol";

interface IFactorGaugeControllerMainchain is IFactorGaugeController {
    function updateVotingResults(
        uint128 wTime, 
        address[] calldata vaults, 
        uint256[] calldata fctrSpeeds
    ) external;
}

