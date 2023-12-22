// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

import "./IDCT.sol";
import "./ILiquidationPool.sol";

import "./TransferHelper.sol";

import "./OwnableUpgradeable.sol";


contract LiquidationPool is OwnableUpgradeable, ILiquidationPool {

    address internal pledgeManager;
    address internal feesDistributor;
    address internal liquidator;

    IDCT internal dctToken;

    uint256 public totalDebt;
    uint256 public totalAccruedFees;

    error LP_NOT_PM();
    error LP_NOT_L();
    error LP_REPAY_TOO_MUCH();

    function initialize(
        address _dctToken,
        address _pledgeManager,
        address _feesDistributor,
        address _liquidator
    ) external initializer {
        __Ownable_init();

        dctToken        = IDCT(_dctToken);
        pledgeManager   = _pledgeManager;
        feesDistributor = _feesDistributor;
        liquidator      = _liquidator;
    }

    function withdrawCollateral(address _to, address _token, uint256 _amount) external {
        if (msg.sender != liquidator) { revert LP_NOT_L(); }

        TransferHelper.safeTransfer(_token, _to, _amount);
    }

    function repayDebt(uint256 _amount) external {
        if (msg.sender != liquidator) { revert LP_NOT_L(); }

        if (totalAccruedFees > 0) {
            if (_amount >= totalAccruedFees) {
                TransferHelper.safeTransferFrom(address(dctToken), msg.sender, feesDistributor, totalAccruedFees);
                _amount -= totalAccruedFees;
                totalAccruedFees = 0;
            } else {
                TransferHelper.safeTransferFrom(address(dctToken), msg.sender, feesDistributor, _amount);
                totalAccruedFees -= _amount;
                _amount = 0;
            }
        }

        if (_amount > totalDebt) {
            revert LP_REPAY_TOO_MUCH();
        }

        dctToken.burn(msg.sender, _amount);

        totalDebt -= _amount;
    }

    function addDebtToPool(uint256 _amount, uint256 _accruedFees) external override {
        if (msg.sender != pledgeManager) { revert LP_NOT_PM(); }

        totalDebt += _amount;
        totalAccruedFees += _accruedFees;
    }
}

