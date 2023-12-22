// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./ERC20_IERC20.sol";
import "./ITreasury.sol";
import "./IDeployment.sol";
import "./IUniswapV2Router.sol";
import "./Deployment.sol";

import "./UmamiAccessControlled.sol";


interface ICurve {
    function add_liquidity(address pool, uint256[3] memory _deposit_amounts, uint256 min_mint_amount) external returns (uint256);
    function remove_liquidity(address pool, uint256 _burn_amount, uint256[3] memory _min_amounts) external returns (uint256[3] memory);
    function remove_liquidity_one_coin(address _pool, uint256 _burn_amount, int128 i, uint256 _min_amount) external returns (uint256);
}

interface ISorbettiere {
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 remainingIceTokenReward;
    }

    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function pendingIce(uint256 _pid, address _user) external view returns (uint256);
    function userInfo(uint256 pool, address user) external returns (UserInfo memory);
}

contract AbraMimDeployment is Deployment {
    using SafeERC20 for IERC20;

    address constant mim = 0xFEa7a6a0B346362BF88A9e4A88416B77a57D6c2A;
    address constant spell = 0x3E6648C5a70A150A88bCE65F4aD4d506Fe15d2AF;
    address constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address constant curve = 0x7544Fe3d184b6B55D6B36c3FCA1157eE0Ba30287;
    address constant mim2CrvPool = 0x30dF229cefa463e991e29D42DB0bae2e122B2AC7;
    address constant abraSorbettiere = 0x839De324a1ab773F76a53900D70Ac1B913d2B387;

    constructor(
        IDeploymentManager manager, 
        ITreasury treasury, 
        address sushiRouter) Deployment(manager, treasury, sushiRouter) {}

    function deposit(uint256 amount, bool fromTreasury) public override onlyDepositWithdrawer {
        if (fromTreasury) {
            treasury.manage(mim, amount);
        } else {
            IERC20(mim).safeTransferFrom(msg.sender, address(this), amount);
        }
        _deposit(amount);
    }

    function _deposit(uint256 amount) internal {
        uint256[3] memory depositAmounts;
        depositAmounts[0] = amount;
        depositAmounts[1] = 0;
        depositAmounts[2] = 0;

        // Deposit MIM into MIM-2Crv pool
        uint256 amountWithSlippage = getSlippageAdjustedAmount(amount, 10 /* 1% */);
        IERC20(mim).approve(curve, amount);
        uint256 mim2CrvAmount = ICurve(curve).add_liquidity(mim2CrvPool, depositAmounts, amountWithSlippage);

        // Deposit MIM-2Crv tokens into Abracadabra staking contract
        IERC20(mim2CrvPool).approve(abraSorbettiere, mim2CrvAmount);
        ISorbettiere(abraSorbettiere).deposit(0, mim2CrvAmount);

        // Deposit will claim pending SPELL, so handle it
        dumpSpell();

        emit Deposit(amount);
    }

    function withdraw(uint256 amount) public override onlyDepositWithdrawer {
        ISorbettiere(abraSorbettiere).withdraw(0, amount);
        uint256 amountWithSlippage = getSlippageAdjustedAmount(amount, 10 /* 1% */);
        IERC20(mim2CrvPool).approve(curve, amount);
        uint256 outputAmount = ICurve(curve).remove_liquidity_one_coin(mim2CrvPool, amount, 0, amountWithSlippage);
        IERC20(mim).safeTransfer(address(treasury), outputAmount);

        // Withdraw will claim pending SPELL, so handle it
        dumpSpell();

        emit Withdraw(amount);
    }

    function withdrawAll(bool) external override onlyDepositWithdrawer {
        uint256 amount = balance(address(0));
        withdraw(amount);
    }

    function harvest(bool dumpTokensForWeth) public override onlyDepositWithdrawer {
        uint256 reward = pendingRewards(address(0));
        ISorbettiere(abraSorbettiere).withdraw(0, 0);
        // Dump SPELL for wETH
        if (reward > 0) {
            if (dumpTokensForWeth) {
                uint256 wethAmount = dumpSpell();
                emit HarvestReward(weth, wethAmount);
            }
            else {
                distributeToken(spell, reward);
                emit HarvestReward(spell, reward);
            }
        }
        emit Harvest(dumpTokensForWeth);
    }

    function dumpSpell() internal returns (uint256) {
        uint256 amount = IERC20(spell).balanceOf(address(this));
        if (amount == 0) return 0;
        address[] memory path = new address[](2);
        path[0] = spell;
        path[1] = weth;
        uint256 wethAmount = swapToken(path, amount, 0);
        distributeToken(weth, wethAmount);
        return wethAmount;
    }

    function compound() external override onlyDepositWithdrawer {
        uint256 reward = pendingRewards(address(0));
        ISorbettiere(abraSorbettiere).withdraw(0, 0);
        address[] memory path = new address[](3);
        path[0] = spell;
        path[1] = weth;
        path[2] = mim;
        uint256 wethAmount = swapToken(path, reward, 0);
        _deposit(wethAmount);
    }

    function balance(address) public override returns (uint256) {
        ISorbettiere.UserInfo memory info = ISorbettiere(abraSorbettiere).userInfo(0, address(this));
        return info.amount;
    }

    function pendingRewards(address) public override view returns (uint256) {
        return ISorbettiere(abraSorbettiere).pendingIce(0, address(this));
    }
}
