// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./Address.sol";
import "./IPositionVault.sol";
import "./IOrderVault.sol";

import "./ISettingsManager.sol";

import {Constants} from "./Constants.sol";
import {OrderStatus, PositionTrigger, TriggerInfo, PaidFees} from "./structs.sol";

contract Reader is Constants {
    struct AccruedFees {
        uint256 positionFee;
        uint256 borrowFee;
        int256 fundingFee;
    }

    IOrderVault private orderVault;
    IPositionVault private positionVault;
    ISettingsManager private settingsManager;

    bool private isInitialized;

    function initialize(IPositionVault _positionVault, IOrderVault _orderVault, ISettingsManager _settingsManager) external {
        require(!isInitialized, "initialized");
        require(Address.isContract(address(_positionVault)), "vault invalid");
        require(Address.isContract(address(_orderVault)), "vaultUtils invalid");
        positionVault = _positionVault;
        orderVault = _orderVault;
        settingsManager = _settingsManager;
        isInitialized = true;
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
}

