// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { OwnerPausable } from "./OwnerPausable.sol";
import { BlockContext } from "./BlockContext.sol";
import { UserAccountStorage } from "./UserAccountStorage.sol";
import { IUserAccount } from "./IUserAccount.sol";
import { IClearingHouse } from "./IClearingHouse.sol";
import { IRewardMiner } from "./IRewardMiner.sol";
import { IVault } from "./IVault.sol";
import { DataTypes } from "./DataTypes.sol";
import { TransferHelper } from "./TransferHelper.sol";
import { SafeERC20Upgradeable, IERC20Upgradeable } from "./SafeERC20Upgradeable.sol";

// never inherit any new stateful contract. never change the orders of parent stateful contracts
contract UserAccount is IUserAccount, BlockContext, OwnerPausable, UserAccountStorage {
    function initialize(address trader, address agent) external initializer {
        __OwnerPausable_init();
        _agent = agent;
        _trader = trader;
    }

    receive() external payable {}

    modifier onlyAgent() {
        // NO_NA: not priceAdmin
        require(_msgSender() == _agent, "NO_NA");
        _;
    }

    function getAgent() external view returns (address) {
        return _agent;
    }

    function getTrader() external view returns (address) {
        return _trader;
    }

    function getLastTimestamp() external view returns (uint256) {
        return _lastTimestamp;
    }

    function settleLastTimestamp() external override onlyAgent {
        _lastTimestamp = _blockTimestamp();
    }

    function openPosition(
        address clearingHouse,
        address baseToken,
        bool isBaseToQuote,
        uint256 quote
    ) external override onlyAgent returns (bool) {
        IClearingHouse(clearingHouse).openPosition(
            DataTypes.OpenPositionParams({
                baseToken: baseToken,
                isBaseToQuote: isBaseToQuote,
                isExactInput: !isBaseToQuote,
                amount: quote,
                oppositeAmountBound: 0,
                deadline: _blockTimestamp() + 60,
                sqrtPriceLimitX96: 0,
                referralCode: ""
            })
        );
        return true;
    }

    function closePosition(address clearingHouse, address baseToken) external override returns (bool) {
        IClearingHouse(clearingHouse).closePosition(
            DataTypes.ClosePositionParams({
                baseToken: baseToken,
                sqrtPriceLimitX96: 0,
                oppositeAmountBound: 0,
                deadline: _blockTimestamp() + 60,
                referralCode: ""
            })
        );
        return true;
    }

    function withdrawAll(
        address clearingHouse,
        address baseToken
    ) external override returns (address token, uint256 amount) {
        //withdraw
        address vault = IClearingHouse(clearingHouse).getVault();
        token = IVault(vault).getSettlementToken();
        if (token != IVault(vault).getWETH9()) {
            IVault(vault).withdrawAll(token, baseToken);
            amount = IERC20Upgradeable(token).balanceOf(address(this));
            TransferHelper.safeTransfer(token, _agent, amount);
        } else {
            IVault(vault).withdrawAllEther(baseToken);
            amount = address(this).balance;
            TransferHelper.safeTransferETH(_agent, amount);
        }
    }

    function withdraw(
        address clearingHouse,
        address baseToken,
        uint256 amountArg
    ) external override returns (address token, uint256 amount) {
        //withdraw
        address vault = IClearingHouse(clearingHouse).getVault();
        token = IVault(vault).getSettlementToken();
        if (token != IVault(vault).getWETH9()) {
            IVault(vault).withdraw(token, amountArg, baseToken);
            TransferHelper.safeTransfer(token, _agent, amountArg);
        } else {
            IVault(vault).withdrawEther(amountArg, baseToken);
            TransferHelper.safeTransferETH(_agent, amountArg);
        }
        amount = amountArg;
    }

    function claimReward(address clearingHouse) external override onlyAgent returns (uint256 amount) {
        IRewardMiner rewardMiner = IRewardMiner(IClearingHouse(clearingHouse).getRewardMiner());
        address pNFTtoken = rewardMiner.getPNFTToken();
        rewardMiner.claim();
        amount = IERC20Upgradeable(pNFTtoken).balanceOf(address(this));
        TransferHelper.safeTransfer(pNFTtoken, _trader, amount);
    }
}

