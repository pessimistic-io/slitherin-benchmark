// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.13;

import "./SafeERC20Upgradeable.sol";

interface IRoyaltyDistributorV1 {
    event Distributed(uint256 indexed originalMintersPoolShare, uint256 indexed etherealSpheresPoolShare);

    function initialize(address weth_, address originalMintersPool_, address etherealSpheresPool_) external;
    function distribute() external;
}
