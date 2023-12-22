// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {Strategy} from "./Strategy.sol";
import {IBalancerPool} from "./IBalancerPool.sol";
import {IBalancerVault} from "./IBalancerVault.sol";
import {IBalancerGauge, IBalancerGaugeFactory} from "./IBalancerGauge.sol";

contract StrategyBalancer is Strategy {
    error LpTokenPriceSlipped();

    string public name;
    IBalancerVault public vault;
    IBalancerGauge public gauge;
    IBalancerPool public pool;
    bytes32 public poolId;
    uint256 public kind;
    address public inputAsset;

    constructor(address _strategyHelper, address _vault, address _gaugeFactory, address _pool, address _inputAsset) Strategy(_strategyHelper) {
        vault = IBalancerVault(_vault);
        gauge = IBalancerGauge(IBalancerGaugeFactory(_gaugeFactory).getPoolGauge(_pool));
        pool = IBalancerPool(_pool);
        poolId = IBalancerPool(_pool).getPoolId();
        inputAsset = _inputAsset;
        name = IERC20(_pool).name();
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        uint256 value = gauge.balanceOf(address(this)) * getPoolPrice() / 1e18;
        return sha * value / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        earn();
        pull(IERC20(ast), msg.sender, amt);
        uint256 tma = gauge.balanceOf(address(this));
        uint256 slp = getSlippage(dat);
        uint256 bal = _joinPool(ast, amt, slp);
        pool.approve(address(gauge), bal);
        gauge.deposit(bal);
        return tma == 0 ? bal : bal * totalShares / tma;
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        earn();
        uint256 slp = getSlippage(dat);
        uint256 tma = gauge.balanceOf(address(this));
        uint256 amt = sha * tma / totalShares;
        gauge.withdraw(amt);

        {
            (address[] memory poolTokens,,) = vault.getPoolTokens(poolId);
            address _inputAsset = inputAsset;
            uint256 length = poolTokens.length;
            uint256[] memory minAmountsOut = new uint256[](length);
            uint256 inputAssetIndex;
            for (uint256 i; i < length; i++) {
                if (poolTokens[i] == _inputAsset) inputAssetIndex = i;
            }

            pool.approve(address(vault), amt);
            vault.exitPool(poolId, address(this), payable(address(this)), IBalancerVault.ExitPoolRequest({
              assets: poolTokens,
              minAmountsOut: minAmountsOut,
              userData: abi.encode(uint256(0), amt, inputAssetIndex),
              toInternalBalance: false
            }));
        }

        uint256 bal = IERC20(inputAsset).balanceOf(address(this));
        {
            uint256 value = amt * getPoolPrice() / 1e18;
            uint256 minValue = strategyHelper.value(inputAsset, bal) * (10000 - slp) / 10000;
            if (value < minValue) revert LpTokenPriceSlipped();
        }

        IERC20(inputAsset).approve(address(strategyHelper), bal);
        return strategyHelper.swap(inputAsset, ast, bal, slp, msg.sender);
    }

    function _earn() internal override {
        gauge.claim_rewards();
        address _inputAsset = inputAsset;
        for (uint256 i = 0; i < 5; i++) {
            address token = gauge.reward_tokens(i);
            if (token == address(0)) break;
            uint256 bal = IERC20(token).balanceOf(address(this));
            if (strategyHelper.value(token, bal) < 0.5e18) return;
            IERC20(token).approve(address(strategyHelper), bal);
            strategyHelper.swap(token, _inputAsset, bal, slippage, address(this));
        }
        uint256 balIa = IERC20(_inputAsset).balanceOf(address(this));
        uint256 balLp = _joinPool(_inputAsset, balIa, slippage);
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

    function _joinPool(address ast, uint256 amt, uint256 slp) internal returns (uint256) {
        address _inputAsset = inputAsset;
        (address[] memory poolTokens,,) = vault.getPoolTokens(poolId);

        IERC20(ast).approve(address(strategyHelper), amt);
        uint256 bal = strategyHelper.swap(ast, _inputAsset, amt, slp, address(this));

        uint length = poolTokens.length;
        uint256[] memory amountsIn = new uint256[](length);
        uint256[] memory maxAmountsIn = new uint256[](length);
        for (uint256 i; i < length; i++) {
            if (poolTokens[i] == _inputAsset) {
                amountsIn[i] = bal;
                maxAmountsIn[i] = bal;
            }
        }

        IERC20(inputAsset).approve(address(vault), bal);
        vault.joinPool(poolId, address(this), address(this), IBalancerVault.JoinPoolRequest({
          assets: poolTokens,
          maxAmountsIn: maxAmountsIn,
          userData: abi.encode(uint256(1), amountsIn, uint256(0)),
          fromInternalBalance: false
        }));

        uint256 lpBal = pool.balanceOf(address(this));
        uint256 value = lpBal * getPoolPrice() / 1e18;
        uint256 minValue = strategyHelper.value(inputAsset, bal) * (10000 - slp) / 10000;
        if (value < minValue) revert LpTokenPriceSlipped();
        return lpBal;
    }

    function getPoolPrice() internal view returns (uint256) {
        (
          address[] memory poolTokens, uint256[] memory balances,
        ) = vault.getPoolTokens(poolId);
        uint256 length = poolTokens.length;
        uint256[] memory weights = pool.getNormalizedWeights();
        uint256 temp = 1e18;
        uint256 invariant = 1e18;
        for (uint256 i = 0; i < length; i++) {
            temp = temp * pow(strategyHelper.price(poolTokens[i]) * 1e18 / weights[i], weights[i]) / 1e18;
            invariant = invariant * pow(balances[i] * 1e18 / (10 ** IERC20(poolTokens[i]).decimals()), weights[i]) / 1e18;
        }
        return invariant * temp / pool.totalSupply();
    }
}

