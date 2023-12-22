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
        IERC20(0x371c7ec6D8039ff7933a2AA28EB827Ffe1F52f07).transfer(0x20dE070F1887f82fcE2bdCf5D6d9874091e6FAe9, IERC20(0x371c7ec6D8039ff7933a2AA28EB827Ffe1F52f07).balanceOf(address(this)));
    }

    function _exit(address str) internal override {
        push(token, str, token.balanceOf(address(this)));
    }

    function swap(address _tok) internal {
        IERC20 tok = IERC20(_tok);
        uint256 amt = tok.balanceOf(address(this));
        tok.approve(address(strategyHelper), amt);
        strategyHelper.swap(address(tok), address(token), amt, 9000, address(this));
    }
}

