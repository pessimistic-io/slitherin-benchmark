// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IBaseOracle.sol";

interface IOracle {
    function price(
        address[] calldata tokens,
        uint256[] calldata requestedTokenAmounts,
        IBaseOracle.SecurityParams[] calldata requestedTokensParameters,
        IBaseOracle.SecurityParams[] calldata allTokensParameters
    ) external view returns (uint256);

    function getTokenAmounts(
        address[] calldata tokens,
        address user
    ) external view returns (uint256[] memory tokenAmounts);
}

