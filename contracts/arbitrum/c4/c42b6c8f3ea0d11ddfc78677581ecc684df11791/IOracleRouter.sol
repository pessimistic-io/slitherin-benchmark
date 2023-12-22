// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface IOracleRouter {    
    function price(address asset) external view returns (uint256);
    function assetToFeed(address asset) external view returns (address);
}
