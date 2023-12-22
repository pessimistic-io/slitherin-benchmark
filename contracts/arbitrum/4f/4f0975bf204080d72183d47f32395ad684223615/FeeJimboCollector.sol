// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import {ILBPair, IERC20} from "./ILBPair.sol";

import {BaseComponent} from "./BaseComponent.sol";
import {IFeeCollector} from "./IFeeCollector.sol";

contract FeeJimboCollector is BaseComponent {
    constructor(address feeManager) BaseComponent(feeManager) {}

    function collectProtocolFees(ILBPair lbPair) external onlyDelegateCall {
        IERC20 tokenX = lbPair.getTokenX();
        IERC20 tokenY = lbPair.getTokenY();

        uint24 floorId = IJUMBO(address(tokenX)).floorBin();

        (uint128 amountXInFloor,) = lbPair.getBin(floorId);
        (uint256 amountYToUnstuckFloor,,) = lbPair.getSwapIn(amountXInFloor + 1, false);

        tokenY.transfer(address(lbPair), amountYToUnstuckFloor);
        lbPair.swap(false, address(this));

        lbPair.collectProtocolFees();

        tokenX.transfer(address(lbPair), tokenX.balanceOf(address(this)));
        lbPair.swap(true, address(this));
    }
}

interface IJUMBO {
    function floorBin() external view returns (uint24);
}

