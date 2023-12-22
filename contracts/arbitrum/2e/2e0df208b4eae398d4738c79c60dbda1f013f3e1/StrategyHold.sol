// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {IERC20} from "./IERC20.sol";

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

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        uint256 slp = getSlippage(dat);
        uint256 tma = token.balanceOf(address(this));
        uint256 amt = sha * tma / totalShares;
        token.approve(address(strategyHelper), amt);
        return strategyHelper.swap(address(token), ast, amt, slp, msg.sender);
    }

    function _earn() internal override {}

    function _move(address old) internal override {
        name = StrategyHold(old).name();
        IERC20 other = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // WETH
        uint256 amt = other.balanceOf(address(this));
        other.approve(address(strategyHelper), amt);
        strategyHelper.swap(address(other), address(token), amt, slippage, address(this));
    }

    function _exit(address str) internal override {
        push(token, str, token.balanceOf(address(this)));
    }
}

