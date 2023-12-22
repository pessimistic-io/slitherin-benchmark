// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGmxVaultPriceFeed {
    function getPrice(
        address _token,
        bool _maximise,
        bool _includeAmmPrice,
        bool
    ) external view returns (uint256);
}
