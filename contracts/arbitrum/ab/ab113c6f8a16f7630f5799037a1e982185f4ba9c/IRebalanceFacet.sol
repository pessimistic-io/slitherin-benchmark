// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IPermissionsFacet.sol";
import "./IDutchAuctionFacet.sol";
import "./ICommonFacet.sol";

interface IRebalanceFacet {
    function rebalance(address callback, bytes calldata data) external;
}

