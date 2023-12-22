// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {Strategy} from "./Strategy.sol";

interface ICurvePoolV2 {
    function token() external view returns (address);
    function coins(uint256) external view returns (address);
    function virtual_price() external view returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function price_oracle(uint256) external view returns (uint256);
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 minDy) external view returns (uint256);
    function add_liquidity(uint256[2] calldata amounts, uint256 minAmount) external;
    function add_liquidity(uint256[3] calldata amounts, uint256 minAmount) external;
    function remove_liquidity_one_coin(uint256 amount, int128 i, uint256 minAmount) external;
}

interface ICurveGauge {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function reward_tokens(uint256) external view returns (address);
    function deposit(uint256) external;
    function withdraw(uint256) external;
    function claim_rewards() external;
}

contract StrategyCurveV2 is Strategy {
    error DidNotConverge();

    string public name;
    ICurvePoolV2 public pool;
    ICurveGauge public gauge;
    uint256 public inputIndex;
    IERC20 public inputAsset;
    IERC20 public poolToken;

    constructor(address _strategyHelper, address _pool, address _gauge, uint256 _inputIndex) Strategy(_strategyHelper) {
        pool = ICurvePoolV2(_pool);
        gauge = ICurveGauge(_gauge);
        inputIndex = _inputIndex;
        inputAsset = IERC20(pool.coins(_inputIndex));
        poolToken = IERC20(_pool);
        name = poolToken.name();
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        uint256 value = gauge.balanceOf(address(this)) * getPoolPrice() / 1e18;
        return sha * value / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        earn();
        // Swap borrowed asset to input asset
        pull(IERC20(ast), msg.sender, amt);
        uint256 tma = gauge.balanceOf(address(this));
        uint256 slp = getSlippage(dat);
        IERC20(ast).approve(address(strategyHelper), amt);
        strategyHelper.swap(ast, address(inputAsset), amt, slp, address(this));

        uint256 lps = deposit(slp);
        return tma == 0 ? lps : lps * totalShares / tma;
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        earn();
        // Withdraw from gauge
        uint256 slp = getSlippage(dat);
        uint256 tma = gauge.balanceOf(address(this));
        uint256 lps = sha * tma / totalShares;
        gauge.withdraw(lps);

        // Burn lp tokens
        poolToken.approve(address(pool), lps);
        uint256 minValue = (lps * getPoolPrice() / 1e18) * (10000 - slp) / 10000;
        uint256 minAmount = minValue * 1e18 / strategyHelper.price(address(inputAsset));
        pool.remove_liquidity_one_coin(lps, int128(int256(inputIndex)), minAmount);

        // Swap to borrowed asset
        uint256 bal = inputAsset.balanceOf(address(this));
        inputAsset.approve(address(strategyHelper), bal);
        return strategyHelper.swap(address(inputAsset), ast, bal, slp, msg.sender);
    }

    function _earn() internal override {
        uint256 slp = slippage;
        gauge.claim_rewards();
        for (uint256 i = 0; i < 5; i++) {
            address token = gauge.reward_tokens(i);
            if (token == address(0)) break;
            uint256 bal = IERC20(token).balanceOf(address(this));
            if (strategyHelper.value(token, bal) < 0.5e18) return;
            IERC20(token).approve(address(strategyHelper), bal);
            strategyHelper.swap(token, address(inputAsset), bal, slp, address(this));
        }
        deposit(slp);
    }

    function _exit(address str) internal override {
        earn();
        uint256 bal = gauge.balanceOf(address(this));
        gauge.withdraw(bal);
        push(poolToken, str, bal);
    }

    function _move(address) internal override {
        uint256 bal = poolToken.balanceOf(address(this));
        totalShares = bal;
        poolToken.approve(address(gauge), bal);
        gauge.deposit(bal);
    }

    function deposit(uint256 slp) internal returns (uint256) {
        // Add liquidity and mint lp tokens
        uint256 bal = inputAsset.balanceOf(address(this));
        if (bal == 0) return 0;
        uint256 minValue = strategyHelper.value(address(inputAsset), bal) * (10000 - slp) / 10000;
        uint256 minLp = minValue * 1e18 / getPoolPrice();
        uint256[2] memory amounts = [uint256(0), 0];
        amounts[inputIndex] = bal;
        inputAsset.approve(address(pool), bal);
        pool.add_liquidity(amounts, minLp);

        // Stake lp tokens into gauge
        uint256 lps = poolToken.balanceOf(address(this));
        poolToken.approve(address(gauge), lps);
        gauge.deposit(lps);
        return lps;
    }

    // Stable2 Pool
    function getPoolPrice() internal view returns (uint256) {
        uint256 p0 = strategyHelper.price(pool.coins(0));
        uint256 p1 = strategyHelper.price(pool.coins(1));
        return pool.get_virtual_price() * min(p0, p1) / 1e18;
    }

    // TriCrypto
    //function getPoolPrice() internal view returns (uint256) {
    //    uint256 p0 = pool.price_oracle(0);
    //    uint256 p1 = pool.price_oracle(1);
    //    return 3 * pool.virtual_price() * cbrt(p0 * p1) / 1e18;
    //}
    //
    //function cbrt(uint256 x) internal pure returns (uint256) {
    //    uint256 d = x / 1e18;
    //    for (uint256 i; i < 255; i++) {
    //        uint256 dPrev = d;
    //        d = d * (2 * 1e18 + x / d * 1e18 / d * 1e18 / d) / (3 * 1e18);
    //        uint256 diff = d > dPrev ? d - dPrev : dPrev - d;
    //        if (diff <= 1 || diff * 1e18 < d) {
    //            return d;
    //        }
    //    }
    //    revert DidNotConverge();
    //}
}

