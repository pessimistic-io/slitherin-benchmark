// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IInvestor} from "./IInvestor.sol";
import {IERC20} from "./IERC20.sol";

contract LiquidationHelper {
    error TransferFailed();

    function lifeBatched(uint256[] calldata positionIds, address investor) external view returns (uint256[] memory) {
        uint256 posLen = positionIds.length;
        uint256[] memory lifeArr = new uint256[](posLen);

        for (uint256 i = 0; i < posLen; i++) {
            (,,,, uint256 borrow) = IInvestor(investor).positions(positionIds[i]);

            if (borrow == 0) {
                lifeArr[i] = 0;
            } else {
                lifeArr[i] = IInvestor(investor).life(positionIds[i]);
            }
        }

        return lifeArr;
    }

    function killBatched(uint256[] calldata positionIds, address investor, address asset, address usr) external {
        for (uint256 i = 0; i < positionIds.length; i++) {
            investor.call(abi.encodeWithSignature("kill(uint256)", positionIds[i]));
        }

        uint256 assetBal = IERC20(asset).balanceOf(address(this));

        if (assetBal > 0) {
            push(usr, asset, assetBal);
        }
    }

    function push(address usr, address asset, uint256 amt) internal {
        if (!IERC20(asset).transfer(usr, amt)) {
            revert TransferFailed();
        }
    }
}

