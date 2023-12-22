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

    function _burn(address, uint256 sha, bytes calldata) internal override returns (uint256) {
        uint256 tma = token.balanceOf(address(this));
        uint256 amt = sha * tma / totalShares;
        token.transfer(msg.sender, amt);
        return amt;
    }

    function _earn() internal override {}

    function _move(address old) internal override {
        name = string(abi.encodePacked("Hold ", StrategyHold(old).name()));
        swap(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        swap(0x912CE59144191C1204E64559FE8253a0e49E6548);
        require(token.balanceOf(address(this)) > 43500e6, "slipped");
    }

    function _exit(address str) internal override {
        push(token, str, token.balanceOf(address(this)));
    }

    function swap(address _tok) internal {
        IERC20 tok = IERC20(_tok);
        uint256 amt = tok.balanceOf(address(this));
        tok.approve(address(strategyHelper), amt);
        strategyHelper.swap(address(tok), address(token), amt, slippage, address(this));
    }
}

