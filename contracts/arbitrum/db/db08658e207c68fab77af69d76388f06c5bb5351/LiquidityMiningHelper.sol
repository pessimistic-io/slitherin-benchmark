// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IPool} from "./IPool.sol";
import {IERC20} from "./IERC20.sol";
import {IStrategyHelper} from "./IStrategyHelper.sol";
import {LiquidityMining} from "./LiquidityMining.sol";

contract LiquidityMiningHelper is Util {
    IERC20 public lpToken;
    IStrategyHelper public strategyHelper;
    LiquidityMining public liquidityMining;

    event FileAddress(bytes32 what, address data);

    constructor() {
        exec[msg.sender] = true;
    }

    function file(bytes32 what, address data) external auth {
        if (what == "exec") exec[data] = !exec[data];
        if (what == "lpToken") lpToken = IERC20(data);
        if (what == "strategyHelper") strategyHelper = IStrategyHelper(data);
        if (what == "liquidityMining") liquidityMining = LiquidityMining(data);
        emit FileAddress(what, data);
    }

    function _wrap(IPool pool, IERC20 tok, uint256 amount) internal returns (uint256) {
        uint256 prev = IERC20(address(pool)).balanceOf(address(this));
        tok.approve(address(pool), amount);
        pool.mint(amount, address(this));
        uint256 next = IERC20(address(pool)).balanceOf(address(this));
        return next - prev;
    }

    function _deposit(uint256 pid, uint256 amount, address to, uint256 lock) internal {
        IERC20 pool = IERC20(address(liquidityMining.token(pid)));
        pool.approve(address(liquidityMining), amount);
        liquidityMining.deposit(pid, amount, to, lock);
    }

    function depositWithWrap(uint256 pid, uint256 amount, address to, uint256 lock) external {
        IPool pool = IPool(address(liquidityMining.token(pid)));
        IERC20 token = IERC20(pool.asset());
        token.transferFrom(msg.sender, address(this), amount);

        uint256 poolAmount = _wrap(pool, token, amount);
        _deposit(pid, poolAmount, to, lock);
    }

    function depositWithZap(
        uint256 pid,
        uint256 amount,
        address to,
        uint256 lock,
        uint256 zapPercent,
        uint256 zapSlippage
    ) external {
        IPool pool = IPool(address(liquidityMining.token(pid)));
        IERC20 token = IERC20(pool.asset());
        token.transferFrom(msg.sender, address(this), amount);

        uint256 zapAmount = amount * zapPercent / 1e18;
        token.approve(address(strategyHelper), zapAmount);
        uint256 lpAmount = strategyHelper.swap(address(token), address(lpToken), zapAmount, zapSlippage, address(this));
        lpToken.approve(address(liquidityMining), lpAmount);
        liquidityMining.depositLp(pid, to, lpAmount);

        if (zapPercent < 1e18) {
            uint256 poolAmount = _wrap(pool, token, amount - zapAmount);
            _deposit(pid, poolAmount, to, lock);
        }
    }
}

