//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20Upgradeable.sol";

import "./IPoolConfigProvider.sol";

contract MockPoolConfigProvider is IPoolConfigProvider {

    uint256 public n;

    function initialize() external {
    }

    function getN(uint64) external view returns(uint256) {
        return n;
    }
}
