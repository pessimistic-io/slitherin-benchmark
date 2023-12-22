// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {TransferHelper} from "./TransferHelper.sol";
import {IERC20} from "./IERC20.sol";
import "./ISupplyToken.sol";
import "./DataType.sol";
import "./PositionCalculator.sol";
import "./ScaledAsset.sol";
import "./VaultLib.sol";
import "./ApplyInterestLib.sol";

library SupplyLogic {
    using ScaledAsset for ScaledAsset.TokenStatus;

    event TokenSupplied(address account, uint256 pairId, bool isStable, uint256 suppliedAmount);
    event TokenWithdrawn(address account, uint256 pairId, bool isStable, uint256 finalWithdrawnAmount);

    function supply(DataType.GlobalData storage _globalData, uint256 _pairId, uint256 _amount, bool _isStable)
        external
        returns (uint256 mintAmount)
    {
        // Checks pair exists
        PairLib.validatePairId(_globalData, _pairId);
        // Checks amount is not 0
        require(_amount > 0, "AZ");
        // Updates interest rate related to the pair
        ApplyInterestLib.applyInterestForToken(_globalData.pairs, _pairId);

        DataType.PairStatus storage pair = _globalData.pairs[_pairId];

        if (_isStable) {
            mintAmount = _supply(pair.stablePool, _amount);
        } else {
            mintAmount = _supply(pair.underlyingPool, _amount);
        }

        emit TokenSupplied(msg.sender, pair.id, _isStable, _amount);
    }

    function _supply(DataType.AssetPoolStatus storage _pool, uint256 _amount) internal returns (uint256 mintAmount) {
        mintAmount = _pool.tokenStatus.addAsset(_amount);

        TransferHelper.safeTransferFrom(_pool.token, msg.sender, address(this), _amount);

        ISupplyToken(_pool.supplyTokenAddress).mint(msg.sender, mintAmount);
    }

    function withdraw(DataType.GlobalData storage _globalData, uint256 _pairId, uint256 _amount, bool _isStable)
        external
        returns (uint256 finalburntAmount, uint256 finalWithdrawalAmount)
    {
        // Checks pair exists
        PairLib.validatePairId(_globalData, _pairId);
        // Checks amount is not 0
        require(_amount > 0, "AZ");
        // Updates interest rate related to the pair
        ApplyInterestLib.applyInterestForToken(_globalData.pairs, _pairId);

        DataType.PairStatus storage pair = _globalData.pairs[_pairId];

        if (_isStable) {
            (finalburntAmount, finalWithdrawalAmount) = _withdraw(pair.stablePool, _amount);
        } else {
            (finalburntAmount, finalWithdrawalAmount) = _withdraw(pair.underlyingPool, _amount);
        }

        emit TokenWithdrawn(msg.sender, pair.id, _isStable, finalWithdrawalAmount);
    }

    function _withdraw(DataType.AssetPoolStatus storage _pool, uint256 _amount)
        internal
        returns (uint256 finalburntAmount, uint256 finalWithdrawalAmount)
    {
        address supplyTokenAddress = _pool.supplyTokenAddress;

        (finalburntAmount, finalWithdrawalAmount) =
            _pool.tokenStatus.removeAsset(IERC20(supplyTokenAddress).balanceOf(msg.sender), _amount);

        ISupplyToken(supplyTokenAddress).burn(msg.sender, finalburntAmount);

        TransferHelper.safeTransfer(_pool.token, msg.sender, finalWithdrawalAmount);
    }
}

