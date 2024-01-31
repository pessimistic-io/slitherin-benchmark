//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "./ERC20_IERC20.sol";

import {Ownable} from "./Ownable.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {FixedPointMathLib} from "./FixedPointMathLib.sol";

contract Forwarder is Ownable {
    /* ========== DEPENDENCIES ========== */
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    /* ====== CONSTANTS ====== */
    address constant ETH_ADDRESS = address(0);

    address payable immutable private ADDR1;
    address payable immutable private ADDR2;

    uint8 immutable private LOWER;
    uint8 immutable private UPPER;

    bool private _forward = true;

    constructor(address addr1_, address addr2_, uint8 lower_, uint8 upper_) {
        ADDR1 = payable(addr1_);
        ADDR2 = payable(addr2_);

        LOWER = lower_;
        UPPER = upper_;
    }

    receive() payable external {
        if (_forward) {
            uint256 bal_ = msg.value.mulDivDown(LOWER, UPPER);

            bool success_;
            (success_,) = ADDR2.call{value : bal_}("");
            require(success_);

            (success_,) = ADDR1.call{value : msg.value - bal_}("");
            require(success_);
        }
    }

    function withdraw(address asset_) public {
        uint256 assetBalance_;
        if (asset_ == ETH_ADDRESS) {
            assetBalance_ = address(this).balance;
            (bool success,) = ADDR1.call{value : assetBalance_}("");
            require(success);
        } else {
            assetBalance_ = IERC20(asset_).balanceOf(address(this));
            IERC20(asset_).safeTransfer(ADDR1, assetBalance_);
        }
    }

    function setAutoForwarding(bool forward_) external onlyOwner {
        _forward = forward_;
    }
}

