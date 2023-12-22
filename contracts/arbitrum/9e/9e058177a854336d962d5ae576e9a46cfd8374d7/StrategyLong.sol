// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {IERC20} from "./IERC20.sol";

contract StrategyLong is Strategy {
    string public name;
    IERC20 public token;

    constructor(address _strategyHelper, address _token) Strategy(_strategyHelper) {
        token = IERC20(_token);
        name = string(abi.encodePacked("Long ", token.symbol()));
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        uint256 val = strategyHelper.value(address(token), token.balanceOf(address(this)));
        return sha * val / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        uint256 tma = token.balanceOf(address(this));
        uint256 slp = getSlippage(dat);
        pull(IERC20(ast), msg.sender, amt);
        IERC20(ast).approve(address(strategyHelper), amt);
        uint256 bal = strategyHelper.swap(ast, address(token), amt, slp, address(this));
        return tma == 0 ? bal : bal * totalShares / tma;
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        uint256 tma = token.balanceOf(address(this));
        uint256 slp = getSlippage(dat);
        uint256 amt = sha * tma / totalShares;
        token.approve(address(strategyHelper), amt);
        return strategyHelper.swap(address(token), ast, amt, slp, msg.sender);
    }

    function _exit(address str) internal override {
        push(token, str, token.balanceOf(address(this)));
    }
}

