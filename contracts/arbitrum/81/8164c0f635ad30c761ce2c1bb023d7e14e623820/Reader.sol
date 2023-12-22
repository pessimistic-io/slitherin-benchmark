// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./AddressUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20.sol";
import "./IPositionVault.sol";
import "./IOrderVault.sol";
import "./IVault.sol";
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
    IVault private vault;
    IERC20 private USDC;
    IERC20 private vUSD;
    IERC20 private vlp;
    IERC20 private vela;
    IERC20 private esVela;

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

    function initializeV3(IVault _vault, IERC20 _USDC, IERC20 _vUSD, IERC20 _vlp, IERC20 _vela, IERC20 _esVela) reinitializer(3) public {
        require(AddressUpgradeable.isContract(address(_esVela)), "esVela invalid");
        require(AddressUpgradeable.isContract(address(_vault)), "Vault invalid");
        require(AddressUpgradeable.isContract(address(_vela)), "vela invalid");
        require(AddressUpgradeable.isContract(address(_vlp)), "vlp invalid");
        require(AddressUpgradeable.isContract(address(_USDC)), "USDC invalid");
        require(AddressUpgradeable.isContract(address(_vUSD)), "vUSD invalid");
        esVela = _esVela;
        vault = _vault;
        vela = _vela;
        vlp = _vlp;
        USDC = _USDC;
        vUSD = _vUSD;
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
        accruedFees.borrowFee = settingsManager.getBorrowFee(position.size, position.lastIncreasedTime, position.tokenId) + position.accruedBorrowFee;
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

    function validateMaxOILimit(address _account, bool _isLong, uint256 _size, uint256 _tokenId) external view returns (uint256, uint256, uint8) {
        uint256 _openInterestPerUser = settingsManager.openInterestPerUser(_account);
        uint256 _maxOpenInterestPerUser = settingsManager.maxOpenInterestPerUser(_account);
        uint256 triggerGasFee = settingsManager.triggerGasFee();
        uint256 marketOrderGasFee = settingsManager.marketOrderGasFee();
        if (_maxOpenInterestPerUser == 0) _maxOpenInterestPerUser = settingsManager.defaultMaxOpenInterestPerUser();
        if (_openInterestPerUser + _size > _maxOpenInterestPerUser)
            return (triggerGasFee, marketOrderGasFee, 1);
        uint256 _openInterestPerAssetPerSide = settingsManager.openInterestPerAssetPerSide(_tokenId, _isLong);
        if (_openInterestPerAssetPerSide + _size > settingsManager.maxOpenInterestPerAssetPerSide(_tokenId, _isLong ))
            return (triggerGasFee, marketOrderGasFee, 2);
        return (triggerGasFee, marketOrderGasFee, 0);
    }

    function getUserBalances(address _account) external view returns (uint256 ethBalance, uint256 usdcBalance, uint256 usdcAllowance, uint256 vusdBalance) {
        ethBalance = _account.balance;
        usdcBalance = USDC.balanceOf(_account);
        usdcAllowance = USDC.allowance(_account, address(vault));
        vusdBalance = vUSD.balanceOf(_account);
    }

    function getUserVelaAndEsVelaInfo(address _account) external view returns (uint256[] memory, uint256[] memory, uint256[] memory, uint256[] memory, uint256[] memory) {
        uint256[] memory balances = new uint256[](2);
        uint256[] memory allowances = new uint256[](2);
        uint256[] memory stakedAmounts = new uint256[](2);
        balances[0] = vela.balanceOf(_account);
        balances[1] = esVela.balanceOf(_account);
        allowances[0] = vela.allowance(_account, address(tokenFarm));
        allowances[1] = esVela.allowance(_account, address(tokenFarm));
        (uint256 velaStakedAmount, uint256 esVelaStakedAmount) = tokenFarm.getStakedVela(_account);
        stakedAmounts[0] = velaStakedAmount;
        stakedAmounts[1] = esVelaStakedAmount;
        (, , uint256[] memory decimals, uint256[] memory pendingTokens) = tokenFarm.pendingTokens(true, _account);
        return (balances, allowances, decimals, pendingTokens, stakedAmounts);
    }

    function getUserVLPInfo(address _account) external view returns (uint256[] memory, uint256[] memory, uint256[] memory) {
        uint256 balance = vlp.balanceOf(_account);
        uint256 allowance = vlp.allowance(_account, address(tokenFarm));
        uint256 vlpPrice = vault.getVLPPrice();
        (uint256 vlpStakedAmount, uint256 startTimestamp) = tokenFarm.getStakedVLP(_account);
        uint256 cooldownDuration = tokenFarm.cooldownDuration();
        uint256[] memory vlpInfo = new uint256[](6);
        vlpInfo[0] = balance;
        vlpInfo[1] = allowance;
        vlpInfo[2] = vlpStakedAmount;
        vlpInfo[3] = vlpPrice;
        vlpInfo[4] = startTimestamp;
        vlpInfo[5] = cooldownDuration;
        (, , uint256[] memory decimals, uint256[] memory pendingTokens) = tokenFarm.pendingTokens(false, _account);
        return (vlpInfo, decimals, pendingTokens);
    }
}

