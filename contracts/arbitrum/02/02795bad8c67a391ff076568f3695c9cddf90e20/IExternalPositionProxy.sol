// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IExternalPositionProxy {
    function getExternalPositionType() external view returns (uint256);
}

