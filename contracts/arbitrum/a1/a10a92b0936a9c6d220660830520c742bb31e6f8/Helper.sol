// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IOracle} from "./IOracle.sol";
import {IPool} from "./IPool.sol";
import {IRateModel} from "./IRateModel.sol";

contract Helper {
    function pool(address pool) public view returns (bool paused, uint256 borrowMin, uint256 amountCap, uint256 index, uint256 shares, uint256 borrow, uint256 supply, uint256 rate, uint256 price) {
        IPool p = IPool(pool);
        paused = p.paused();
        borrowMin = p.borrowMin();
        amountCap = p.amountCap();
        index = p.getUpdatedIndex();
        shares = p.totalSupply();
        borrow = p.totalBorrow() * index / 1e18;
        supply = borrow + IERC20(p.asset()).balanceOf(pool);
        {
            IRateModel rm = IRateModel(p.rateModel());
            rate = supply == 0 ? 0 : rm.rate(borrow * 1e18 / supply);
        }
        {
            IOracle oracle = IOracle(p.oracle());
            price = uint256(oracle.latestAnswer()) * 1e18 / (10 ** oracle.decimals());
        }
    }

    function rateModel(address pool) public view returns (uint256, uint256, uint256, uint256) {
        IPool p = IPool(pool);
        IRateModel rm = IRateModel(p.rateModel());
        return (rm.kink(), rm.base(), rm.low(), rm.high());
    }
}

