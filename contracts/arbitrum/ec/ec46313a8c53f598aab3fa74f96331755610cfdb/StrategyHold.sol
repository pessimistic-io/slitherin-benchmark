// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {IERC20} from "./IERC20.sol";

interface IPair is IERC20 {
    function token0() external view returns (IERC20);
    function token1() external view returns (IERC20);
    function burn(address) external;
}

contract StrategyHold is Strategy {
    string public name = "Hold";
    IERC20 public token;

    constructor(address _strategyHelper, address _token) Strategy(_strategyHelper) {
        token = IERC20(_token);
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        uint256 val = strategyHelper.value(address(token), token.balanceOf(address(this)));
        return sha * val / totalShares;
    }

    function _mint(address, uint256, bytes calldata) internal override returns (uint256) {
        revert("Strategy on hold");
    }

    function _burn(address, uint256 sha, bytes calldata) internal override returns (uint256) {
        uint256 tma = token.balanceOf(address(this));
        uint256 amt = sha * tma / totalShares;
        token.transfer(msg.sender, amt);
        return amt;
    }

    function _earn() internal override {}

    function _move(address old) internal override {
        name = string(abi.encodePacked("Hold ", StrategyHold(old).name()));
        IPair pair = IPair(0xCB0E5bFa72bBb4d16AB5aA0c60601c438F04b4ad);
        pair.transfer(address(pair), pair.balanceOf(address(this)));
        pair.burn(address(this));
        uint256 amt0 = pair.token0().balanceOf(address(this));
        pair.token0().approve(address(strategyHelper), amt0);
        strategyHelper.swap(address(pair.token0()), address(token), amt0, slippage, address(this));
        uint256 amt1 = pair.token1().balanceOf(address(this));
        pair.token1().approve(address(strategyHelper), amt1);
        strategyHelper.swap(address(pair.token1()), address(token), amt1, slippage, address(this));
    }

    function _exit(address str) internal override {
        push(token, str, token.balanceOf(address(this)));
    }
}

