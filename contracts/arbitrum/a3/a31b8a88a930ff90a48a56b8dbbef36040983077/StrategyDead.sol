// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {IERC20} from "./IERC20.sol";

contract StrategyDead is Strategy {
    string public name = "Dead";

    constructor(address _strategyHelper) Strategy(_strategyHelper) {
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        return 0;
    }

    function _mint(address, uint256, bytes calldata) internal override returns (uint256) {
        revert("Strategy on dead");
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        revert("Strategy on dead");
    }
}

