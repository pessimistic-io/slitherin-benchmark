// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./TestDataTypes.sol";

interface ITestHub {

    // --- Functions ---
    function setAddresses(
        address _activePoolAddress
    ) external;

    function swap(
        address _collateral,
        uint256 _amountIn,
        TestDataTypes.SwapParams calldata _swapParams
    ) external returns (uint256);

}

