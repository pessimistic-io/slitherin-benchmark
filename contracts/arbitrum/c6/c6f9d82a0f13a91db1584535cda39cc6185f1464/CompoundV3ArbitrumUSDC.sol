// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./ERC20_IERC20.sol";
import {Defii} from "./Defii.sol";
import "./console.sol";


contract CompoundV3ArbitrumUSDC is Defii {
    IERC20 constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    cToken constant cUSDCv3 =
        cToken(0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA);
    IERC20 constant COMP = IERC20(0x354A6dA3fcde098F8389cad84b0182725c6C91dE);
    Rewards constant rewards =
        Rewards(0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae);

    function hasAllocation() public view override returns (bool) {
        return cUSDCv3.balanceOf(address(this)) > 0;
    }

    function _enter() internal override {
        uint usdcBalance = USDC.balanceOf(address(this));
        cUSDCv3.supply(address(USDC), usdcBalance);
    }

    function _exit() internal override {
        cUSDCv3.withdraw(address(USDC), type(uint).max);
        _harvest();
    }

    function _harvest() internal override {
        rewards.claim(address(cUSDCv3), address(this), true);
        _claimIncentive(COMP);
    }

    function _withdrawFunds() internal override {
        withdrawERC20(USDC);
    }

    function _postInit() internal override {
        USDC.approve(address(cUSDCv3), type(uint).max);
    }
}

interface cToken is IERC20 {
    function supply(address, uint) external;

    function withdraw(address, uint) external;
}

interface Rewards {
    function claim(address, address, bool) external;
}

