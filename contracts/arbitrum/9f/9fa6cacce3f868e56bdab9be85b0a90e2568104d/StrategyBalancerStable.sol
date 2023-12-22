// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {Strategy} from "./Strategy.sol";
import {IBalancerPool} from "./IBalancerPool.sol";
import {IBalancerVault} from "./IBalancerVault.sol";
import {IBalancerGauge, IBalancerGaugeFactory} from "./IBalancerGauge.sol";

contract StrategyBalancerStable is Strategy {
    string public name;
    IBalancerVault public vault;
    IBalancerGauge public gauge;
    IERC20 public pool;
    bytes32 public poolId;
    IERC20 public inputAsset;

    constructor(address _strategyHelper, address _vault, address _gaugeFactory, address _pool, address _inputAsset) Strategy(_strategyHelper) {
        vault = IBalancerVault(_vault);
        gauge = IBalancerGauge(IBalancerGaugeFactory(_gaugeFactory).getPoolGauge(_pool));
        pool = IERC20(_pool);
        poolId = IBalancerPool(_pool).getPoolId();
        inputAsset = IERC20(_inputAsset);
        name = IERC20(_pool).name();
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        uint256 value = strategyHelper.value(address(pool), gauge.balanceOf(address(this)));
        return sha * value / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        earn();
        pull(IERC20(ast), msg.sender, amt);
        uint256 tma = gauge.balanceOf(address(this));
        uint256 slp = getSlippage(dat);
        IERC20(ast).approve(address(strategyHelper), amt);
        uint256 bal = strategyHelper.swap(ast, address(inputAsset), amt, slp, address(this));
        inputAsset.approve(address(strategyHelper), bal);
        uint256 lps = strategyHelper.swap(address(inputAsset), address(pool), bal, slp, address(this));
        pool.approve(address(gauge), lps);
        gauge.deposit(lps);
        return tma == 0 ? lps : lps * totalShares / tma;
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        earn();
        uint256 slp = getSlippage(dat);
        uint256 tma = gauge.balanceOf(address(this));
        uint256 amt = sha * tma / totalShares;
        gauge.withdraw(amt);

        pool.approve(address(strategyHelper), amt);
        uint256 bal = strategyHelper.swap(address(pool), address(inputAsset), amt, slp, address(this));
        inputAsset.approve(address(strategyHelper), bal);
        return strategyHelper.swap(address(inputAsset), ast, bal, slp, msg.sender);
    }

    function _earn() internal override {
        gauge.claim_rewards();
        for (uint256 i = 0; i < 5; i++) {
            address token = gauge.reward_tokens(i);
            if (token == address(0)) break;
            uint256 bal = IERC20(token).balanceOf(address(this));
            if (strategyHelper.value(token, bal) < 0.5e18) return;
            IERC20(token).approve(address(strategyHelper), bal);
            strategyHelper.swap(token, address(inputAsset), bal, slippage, address(this));
        }
        uint256 balIa = inputAsset.balanceOf(address(this));
        inputAsset.approve(address(strategyHelper), balIa);
        uint256 balLp = strategyHelper.swap(address(inputAsset), address(pool), balIa, slippage, address(this));
        pool.approve(address(gauge), balLp);
        gauge.deposit(balLp);
    }

    function _exit(address str) internal override {
        earn();
        uint256 bal = gauge.balanceOf(address(this));
        gauge.withdraw(bal);
        push(IERC20(address(pool)), str, bal);
    }

    function _move(address) internal override {
        uint256 bal = pool.balanceOf(address(this));
        totalShares = bal;
        pool.approve(address(gauge), bal);
        gauge.deposit(bal);
    }
}

