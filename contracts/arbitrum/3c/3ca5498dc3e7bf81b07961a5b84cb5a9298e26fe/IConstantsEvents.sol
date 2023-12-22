// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IConstantsEvents {
    event SetCollateral(address oldAddress, address newAddress);
    event SetLiquidationFee(uint256 oldFee, uint256 newFee);
    event SetProtocolLiquidationShare(uint256 oldShare, uint256 newShare);
    event SetCVA(uint256 oldCVA, uint256 newCVA);
    event SetRequestTimeout(uint256 oldTimeout, uint256 newTimeout);
    event SetMaxOpenPositionsCross(uint256 oldMax, uint256 newMax);
}

