// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./AddressUpgradeable.sol";
import "./Initializable.sol";
import "./IPositionVault.sol";
import "./IOrderVault.sol";

import "./ISettingsManager.sol";

import "./ITokenFarm.sol";

import {Constants} from "./Constants.sol";
import {OrderStatus, PositionTrigger, TriggerInfo, PaidFees} from "./structs.sol";

contract Reader is Constants, Initializable {
    struct AccruedFees {
        uint256 positionFee;
        uint256 borrowFee;
        int256 fundingFee;
    }

    IOrderVault private orderVault;
    IPositionVault private positionVault;
    ISettingsManager private settingsManager;
    ITokenFarm private tokenFarm;

    function initialize(IPositionVault _positionVault, IOrderVault _orderVault, ISettingsManager _settingsManager) public initializer {
        require(AddressUpgradeable.isContract(address(_positionVault)), "positionVault invalid");
        require(AddressUpgradeable.isContract(address(_orderVault)), "orderVault invalid");
        positionVault = _positionVault;
        orderVault = _orderVault;
        settingsManager = _settingsManager;
    }

    function initializeV2(ITokenFarm _tokenFarm) reinitializer(2) public {
        tokenFarm = _tokenFarm; // first caller 2%, resolver 8% and leftover 90% to vlp
        require(AddressUpgradeable.isContract(address(_tokenFarm)), "tokenFarm invalid");
    }


    function getUserAlivePositions(
        address _user
    )
        public
        view
        returns (uint256[] memory, Position[] memory, Order[] memory, PositionTrigger[] memory, PaidFees[] memory, AccruedFees[] memory)
    {
        uint256[] memory posIds = positionVault.getUserPositionIds(_user);
        uint256 length = posIds.length;
        Position[] memory positions_ = new Position[](length);
        Order[] memory orders_ = new Order[](length);
        PositionTrigger[] memory triggers_ = new PositionTrigger[](length);
        PaidFees[] memory paidFees_ = new PaidFees[](length);
        AccruedFees[] memory accruedFees_ = new AccruedFees[](length);
        for (uint i; i < length; ++i) {
            uint256 posId = posIds[i];
            positions_[i] = positionVault.getPosition(posId);
            orders_[i] = orderVault.getOrder(posId);
            triggers_[i] = orderVault.getTriggerOrderInfo(posId);
            paidFees_[i] = positionVault.getPaidFees(posId);
            accruedFees_[i] = getAccruedFee(posId);
        }
        return (posIds, positions_, orders_, triggers_, paidFees_, accruedFees_);
    }

    function getAccruedFee(uint256 _posId) internal view returns (AccruedFees memory){
        Position memory position = positionVault.getPosition(_posId);
        AccruedFees memory accruedFees;
        accruedFees.positionFee = settingsManager.getTradingFee(position.owner, position.tokenId, position.isLong, position.size);
        accruedFees.borrowFee = settingsManager.getBorrowFee(position.size, position.lastIncreasedTime, position.tokenId);
        accruedFees.fundingFee = settingsManager.getFundingFee(position.tokenId, position.isLong, position.size, position.fundingIndex);
        return accruedFees;
    }

    function getGlobalInfo (uint256 _tokenId) external view returns (int256, uint256, uint256, uint256, uint256, uint256) {
        int256 fundingRate = settingsManager.getFundingRate(_tokenId);
        uint256 borrowRate = settingsManager.getBorrowRate(_tokenId);
        uint256 longOpenInterest = settingsManager.openInterestPerAssetPerSide(_tokenId, true);
        uint256 shortOpenInterest = settingsManager.openInterestPerAssetPerSide(_tokenId, false);
        uint256 maxLongOpenInterest = settingsManager.maxOpenInterestPerAssetPerSide(_tokenId, true);
        uint256 maxShortOpenInterest = settingsManager.maxOpenInterestPerAssetPerSide(_tokenId, false);
        return (fundingRate, borrowRate, longOpenInterest, shortOpenInterest, maxLongOpenInterest, maxShortOpenInterest);
    }

    function getUserOpenOrders(
        address _user
    )
        public
        view
        returns (uint256[] memory, Position[] memory, Order[] memory, PositionTrigger[] memory, PaidFees[] memory, AccruedFees[] memory)
    {
        uint256[] memory posIds = positionVault.getUserOpenOrderIds(_user);
        uint256 length = posIds.length;
        Position[] memory positions_ = new Position[](length);
        Order[] memory orders_ = new Order[](length);
        PositionTrigger[] memory triggers_ = new PositionTrigger[](length);
        PaidFees[] memory paidFees_ = new PaidFees[](length);
        AccruedFees[] memory accruedFees_ = new AccruedFees[](length);
        for (uint i; i < length; ++i) {
            uint256 posId = posIds[i];
            positions_[i] = positionVault.getPosition(posId);
            orders_[i] = orderVault.getOrder(posId);
            triggers_[i] = orderVault.getTriggerOrderInfo(posId);
            paidFees_[i] = positionVault.getPaidFees(posId);
            accruedFees_[i] = getAccruedFee(posId);
        }
        return (posIds, positions_, orders_, triggers_, paidFees_, accruedFees_);
    }

    function getFeesFor1CT(address _normal, address _oneCT) external view returns (bool, uint256) {
        uint256 tierVelaPercent = tokenFarm.getTierVela(_normal);
        uint256 deductFeePercentForNormal = settingsManager.deductFeePercent(_normal);
        uint256 deductFeePercentForOneCT = settingsManager.deductFeePercent(_oneCT);
        if (tierVelaPercent * (BASIS_POINTS_DIVISOR - deductFeePercentForNormal) / BASIS_POINTS_DIVISOR != (BASIS_POINTS_DIVISOR - deductFeePercentForOneCT)) {
            return (true, BASIS_POINTS_DIVISOR - tierVelaPercent * (BASIS_POINTS_DIVISOR - deductFeePercentForNormal) / BASIS_POINTS_DIVISOR);
        } else {
            return (false, 0);
        }
    }
}

