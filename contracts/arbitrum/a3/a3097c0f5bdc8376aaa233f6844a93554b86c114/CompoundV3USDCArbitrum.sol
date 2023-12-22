// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import "./errors.sol";
import {ICompoundV3USDC} from "./interfaces.sol";
import {BaseLendingArbitrum} from "./BaseLendingArbitrum.sol";
import {IComet, ICompoundRewards} from "./ICompoundV3.sol";

contract CompoundV3USDCArbitrum is ICompoundV3USDC, BaseLendingArbitrum {
    using SafeERC20 for IERC20;

    IComet constant comet = IComet(0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA);
    ICompoundRewards constant compoundRewards =
        ICompoundRewards(0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae);

    function supplyCompoundV3USDC() external onlyOwner {
        _supplyCompoundV3USDC(WBTC);
    }

    function borrowCompoundV3USDC(uint256 amount) external onlyOwner {
        comet.withdrawTo(owner, address(USDC), amount);
    }

    function repayCompoundV3USDC() external onlyOwner {
        uint256 balance = USDC.balanceOf(address(this));
        if (balance == 0) return;

        uint256 debt = comet.borrowBalanceOf(address(this));
        if (debt == 0) return;

        if (balance > debt) {
            comet.supply(address(USDC), debt);
            _withdrawERC20(USDC);
        } else {
            comet.supply(address(USDC), balance);
        }
    }

    function withdrawCompoundV3USDC(
        IERC20 token,
        uint256 amount
    ) external onlyOwner {
        if (amount == 0) {
            (uint128 userBalance, ) = comet.userCollateral(
                address(this),
                address(token)
            );
            amount = uint256(userBalance);
        }
        comet.withdrawTo(owner, address(token), amount);
    }

    function claimRewardsCompoundV3USDC() external {
        compoundRewards.claimTo(address(comet), address(this), owner, true);
    }

    function _supplyCompoundV3USDC(IERC20 token) internal {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return;
        comet.supply(address(token), balance);
    }

    function _postInit() internal virtual override {
        WBTC.safeApprove(address(comet), type(uint256).max);
        USDC.safeApprove(address(comet), type(uint256).max);
    }
}

