// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IGMXVaultPriceFeed {

    function getPrice(address _token, bool _maximise, bool _includeAmmPrice, bool) external view returns (uint256);   
}
