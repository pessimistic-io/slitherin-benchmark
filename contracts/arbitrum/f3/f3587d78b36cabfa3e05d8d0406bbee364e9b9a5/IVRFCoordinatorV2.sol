// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IVRFCoordinatorV2 {

    function getConfig() external view returns (uint16 minimumRequestConfirmations, uint32 maxGasLimit, uint32 stalenessSeconds, uint32 gasAfterPaymentCalculation);

}

