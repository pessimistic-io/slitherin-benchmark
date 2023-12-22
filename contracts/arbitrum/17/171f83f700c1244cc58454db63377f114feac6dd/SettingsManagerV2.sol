// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

import "./OwnableUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./ISettingsManagerV2.sol";
import "./IPositionKeeperV2.sol";
import "./IVaultV2.sol";
import "./IReferralSystem.sol";

import {Constants} from "./Constants.sol";

contract SettingsManagerV2 is ISettingsManagerV2, Constants, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    address public RUSD;
    IPositionKeeperV2 public positionKeeper;
    address public positionHandler;
    IVaultV2 public vault;

    address public referralSystem;
    address public override feeManager;

    bool public override isEnableNonStableCollateral;
    bool public override marketOrderEnabled;
    bool public override referEnabled;
    bool public override pauseForexForCloseTime;
    bool public override isEnableConvertRUSD;
    bool public override isEnableUnstaking;
    bool public override isEmergencyStop;

    uint256 public maxOpenInterestPerUser;
    uint256 public priceMovementPercent;

    uint256 public override closeDeltaTime;
    uint256 public override cooldownDuration;
    uint256 public override delayDeltaTime;
    uint256 public override depositFee;
    uint256 public override feeRewardBasisPoints;
    uint256 public override liquidationFeeUsd;
    uint256 public override stakingFee;
    uint256 public override unstakingFee;
    uint256 public override triggerGasFee;
    uint256 public override positionDefaultSlippage;
    uint256 public override maxProfitPercent;
    uint256 public override basisFundingRateFactor;
    uint256 public override maxFundingRate;
    uint256 public override defaultBorrowFeeFactor; // 0.01% per hour

    mapping(address => bool) public override isCollateral;
    mapping(address => bool) public override isTradable;
    mapping(address => bool) public override isStable;
    mapping(address => bool) public override isStaking;

    mapping(address => mapping(bool => uint256)) public maxOpenInterestPerAssetPerSide;
    mapping(address => mapping(bool => uint256)) public openInterestPerAssetPerSide;

    mapping(address => mapping(bool => uint256)) public override cumulativeFundingRates;
    mapping(address => mapping(bool => uint256)) public override marginFeeBasisPoints; // = 100; // 0.1%
    mapping(address => uint256) public override lastFundingTimes;
    mapping(address => uint256) public override fundingRateFactor;
    mapping(address => uint256) public override borrowFeeFactor;
    mapping(address => int256) public override fundingIndex;

    mapping(bool => uint256) public maxOpenInterestPerSide;
    mapping(bool => uint256) public override openInterestPerSide;

    //Max price updated delay time vs block.timestamp
    uint256 public override maxPriceUpdatedDelay;
    mapping(address => uint256) public liquidateThreshold;
    mapping(address => uint256) public maxOpenInterestPerAsset;
    mapping(address => uint256) public override openInterestPerAsset;
    mapping(address => uint256) public override openInterestPerUser;

    mapping(address => EnumerableSetUpgradeable.AddressSet) private _delegatesByMaster;
    uint256 public override maxTriggerPriceLength;
    uint256[50] private __gap;

    event FinalInitialized(
        address RUSD,
        address positionHandler,
        address positionKeeper,
        address vault
    );
    event SetReferralSystem(address indexed referralSystem);
    event SetEnableNonStableCollateral(bool isEnabled);
    event SetReferEnabled(bool referEnabled);
    event EnableForexMarket(bool _enabled);
    event EnableMarketOrder(bool _enabled);
    event SetDepositFee(uint256 indexed fee);
    event SetEnableCollateral(address indexed token, bool isEnabled);
    event SetEnableTradable(address indexed token, bool isEnabled);
    event SetEnableStable(address indexed token, bool isEnabled);
    event SetEnableStaking(address indexed token, bool isEnabled);
    event SetEnableUnstaking(bool isEnabled);
    event SetFundingRateFactor(address indexed token, uint256 fundingRateFactor);
    event SetLiquidationFeeUsd(uint256 indexed _liquidationFeeUsd);
    event SetMarginFeeBasisPoints(address indexed token, bool isLong, uint256 marginFeeBasisPoints);
    event SetMaxOpenInterestPerAsset(address indexed token, uint256 maxOIAmount);
    event SetMaxOpenInterestPerSide(bool isLong, uint256 maxOIAmount);
    event SetMaxOpenInterestPerUser(uint256 maxOIAmount);
    event SetStakingFee(uint256 indexed fee);
    event SetUnstakingFee(uint256 indexed fee);
    event SetTriggerGasFee(uint256 indexed fee);
    event SetVaultSettings(uint256 indexed cooldownDuration, uint256 feeRewardBasisPoints);
    event UpdateFundingRate(address indexed token, bool isLong, uint256 fundingRate, uint256 lastFundingTime);
    event UpdateTotalOpenInterest(address indexed token, bool isLong, uint256 amount);
    event UpdateCloseDeltaTime(uint256 deltaTime);
    event UpdateDelayDeltaTime(uint256 deltaTime);
    event UpdateFeeManager(address indexed feeManager);
    event UpdateThreshold(uint256 oldThreshold, uint256 newThredhold);
    event SetDefaultPositionSlippage(uint256 positionDefaultSlippage);
    event SetMaxPriceUpdatedDelay(uint256 maxPriceUpdatedDelay);
    event SetEnableConvertRUSD(bool enableConvertRUSD);
    event SetEmergencyStop(bool isEmergencyStop);
    event SetPriceMovementPercent(uint256 priceMovementPercent);
    event UpdateMaxProfitPercent(uint256 maxProfitPercent);
    event UpdateFunding(address indexed token, int256 fundingIndex);
    event SetMaxFundingRate(uint256 maxFundingRate);
    event SetMaxOpenInterestPerAssetPerSide(address indexed token, bool isLong, uint256 maxOIAmount);
    event SetBorrowFeeFactor(address indexToken, uint256 feeFactor);
    event SetMaxTriggerPriceLength(uint256 maxTriggerPriceLength);

    modifier hasPermission() {
        require(msg.sender == address(positionHandler), "Only position handler has access");
        _;
    }

    function initialize(address _RUSD) public initializer {
        require(AddressUpgradeable.isContract(_RUSD), "RUSD invalid");
        __Ownable_init();
        RUSD = _RUSD;
        _setMaxFundingRate(MAX_FUNDING_RATE);
        marketOrderEnabled = true;
        isEnableNonStableCollateral = false;
        maxPriceUpdatedDelay = 5 minutes;
        defaultBorrowFeeFactor = 10;
        basisFundingRateFactor = 10000;
        maxProfitPercent = 10000; //10%
        positionDefaultSlippage = BASIS_POINTS_DIVISOR / 200; // 0.5%
        stakingFee = 300; // 0.3%
        feeRewardBasisPoints = 50000; // 50%
        depositFee = 300; // 0.3%
        delayDeltaTime = 1 minutes;
        cooldownDuration = 3 hours;
        priceMovementPercent = 500; // 0.5%
    }

    function finalInitialize(
        address _positionHandler,
        address _positionKeeper,
        address _vault
    ) public onlyOwner {
        require(AddressUpgradeable.isContract(_positionHandler), "Invalid positionHandler");
        positionHandler = _positionHandler;

        require(AddressUpgradeable.isContract(_positionKeeper), "Invalid positionKeeper");
        positionKeeper = IPositionKeeperV2(_positionKeeper);

        require(AddressUpgradeable.isContract(_vault), "Invalid vault");
        vault = IVaultV2(_vault);
        emit FinalInitialized(
            RUSD,
            _positionHandler,
            _positionKeeper,
            _vault
        );
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    //Config functions
    function setReferralSystem(address _referralSystem) external onlyOwner {
        require(AddressUpgradeable.isContract(_referralSystem), "ReferralSystem invalid");
        referralSystem = _referralSystem;
        emit SetReferralSystem(_referralSystem);
    }

    function setEnableNonStableCollateral(bool _isEnabled) external onlyOwner {
        isEnableNonStableCollateral = _isEnabled;
        emit SetEnableNonStableCollateral(_isEnabled);
    }

    function setPositionDefaultSlippage(uint256 _slippage) external onlyOwner {
        require(_slippage >= 0 && _slippage < BASIS_POINTS_DIVISOR, "Invalid slippage");
        positionDefaultSlippage = _slippage;
        emit SetDefaultPositionSlippage(_slippage);
    }

    function setMaxPriceUpdatedDelay(uint256 _maxPriceUpdatedDelay) external onlyOwner {
        maxPriceUpdatedDelay = _maxPriceUpdatedDelay;
        emit SetMaxPriceUpdatedDelay(_maxPriceUpdatedDelay);
    }

    function setEnableUnstaking(bool _isEnable) external onlyOwner {
        isEnableUnstaking = _isEnable;
        emit SetEnableUnstaking(_isEnable);
    }

    function setStakingFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_STAKING_FEE, "Staking fee is bigger than max");
        stakingFee = _fee;
        emit SetStakingFee(_fee);
    }

    function setUnstakingFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_STAKING_FEE, "Unstaking fee is bigger than max");
        unstakingFee = _fee;
        emit SetUnstakingFee(_fee);
    }

    function setEmergencyStop(bool _isEmergencyStop) external onlyOwner {
        isEmergencyStop = _isEmergencyStop;
    }

    function setMaxProfitPercent(uint256 _maxProfitPercent) external onlyOwner {
        maxProfitPercent = _maxProfitPercent;
        emit UpdateMaxProfitPercent(_maxProfitPercent);
    }

    function setMaxFundingRate(uint256 _maxFundingRate) external onlyOwner {
        _setMaxFundingRate(_maxFundingRate);
    }

    function setMaxOpenInterestPerAssetPerSide(
        address _token,
        bool _isLong,
        uint256 _maxAmount
    ) external onlyOwner {
        maxOpenInterestPerAssetPerSide[_token][_isLong] = _maxAmount;
        emit SetMaxOpenInterestPerAssetPerSide(_token, _isLong, _maxAmount);
    }
    //End config functions

    function delegate(address[] memory _delegates) external {
        for (uint256 i = 0; i < _delegates.length; ++i) {
            EnumerableSetUpgradeable.add(_delegatesByMaster[msg.sender], _delegates[i]);
        }
    }

    function decreaseOpenInterest(
        address _token,
        address _sender,
        bool _isLong,
        uint256 _amount
    ) external override hasPermission {
        if (openInterestPerUser[_sender] < _amount) {
            openInterestPerUser[_sender] = 0;
        } else {
            openInterestPerUser[_sender] -= _amount;
        }

        if (openInterestPerAsset[_token] < _amount) {
            openInterestPerAsset[_token] = 0;
        } else {
            openInterestPerAsset[_token] -= _amount;
        }
        
        if (openInterestPerSide[_isLong] < _amount) {
            openInterestPerSide[_isLong] = 0;
        } else {
            openInterestPerSide[_isLong] -= _amount;
        }

        emit UpdateTotalOpenInterest(_token, _isLong, _amount);
    }

    function enableMarketOrder(bool _enable) external onlyOwner {
        marketOrderEnabled = _enable;
        emit EnableMarketOrder(_enable);
    }

    function enableForexMarket(bool _enable) external onlyOwner {
        pauseForexForCloseTime = _enable;
        emit EnableForexMarket(_enable);
    }

    function increaseOpenInterest(
        address _token,
        address _sender,
        bool _isLong,
        uint256 _amount
    ) external override hasPermission {
        openInterestPerUser[_sender] += _amount;
        openInterestPerAsset[_token] += _amount;
        openInterestPerSide[_isLong] += _amount;
        openInterestPerAssetPerSide[_token][_isLong] += _amount;
        emit UpdateTotalOpenInterest(_token, _isLong, _amount);
    }

    function setFeeManager(address _feeManager) external onlyOwner {
        feeManager = _feeManager;
        emit UpdateFeeManager(_feeManager);
    }

    function setVaultSettings(uint256 _cooldownDuration, uint256 _feeRewardsBasisPoints) external onlyOwner {
        require(_feeRewardsBasisPoints >= 0 && _feeRewardsBasisPoints <= MAX_FEE_REWARD_BASIS_POINTS, "Invalid feeRewardsBasisPoints");
        cooldownDuration = _cooldownDuration;
        feeRewardBasisPoints = _feeRewardsBasisPoints;
        emit SetVaultSettings(cooldownDuration, feeRewardBasisPoints);
    }

    function setCloseDeltaTime(uint256 _deltaTime) external onlyOwner {
        require(_deltaTime <= MAX_DELTA_TIME, "CloseDeltaTime is bigger than max");
        closeDeltaTime = _deltaTime;
        emit UpdateCloseDeltaTime(_deltaTime);
    }

    function setDelayDeltaTime(uint256 _deltaTime) external onlyOwner {
        require(_deltaTime <= MAX_DELTA_TIME, "DelayDeltaTime is bigger than max");
        delayDeltaTime = _deltaTime;
        emit UpdateDelayDeltaTime(_deltaTime);
    }

    function setDepositFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_DEPOSIT_FEE, "Deposit fee is bigger than max");
        depositFee = _fee;
        emit SetDepositFee(_fee);
    }

    function setEnableCollateral(address _token, bool _isEnabled) external onlyOwner {
        isCollateral[_token] = _isEnabled;
        emit SetEnableCollateral(_token, _isEnabled);
    }

    function setEnableTradable(address _token, bool _isEnabled) external onlyOwner {
        isTradable[_token] = _isEnabled;
        emit SetEnableTradable(_token, _isEnabled);
    }

    function setEnableStable(address _token, bool _isEnabled) external onlyOwner {
        isStable[_token] = _isEnabled;
        emit SetEnableStable(_token, _isEnabled);
    }

    function setEnableStaking(address _token, bool _isEnabled) external onlyOwner {
        isStaking[_token] = _isEnabled;
        emit SetEnableStaking(_token, _isEnabled);
    }

    function setFundingRateFactor(address _token, uint256 _fundingRateFactor) external onlyOwner {
        require(_fundingRateFactor <= MAX_FUNDING_RATE_FACTOR, "FundingRateFactor should be smaller than MAX");
        fundingRateFactor[_token] = _fundingRateFactor;
        emit SetFundingRateFactor(_token, _fundingRateFactor);
    }

    function setLiquidateThreshold(uint256 _newThreshold, address _token) external onlyOwner {
        emit UpdateThreshold(liquidateThreshold[_token], _newThreshold);
        require(_newThreshold < BASIS_POINTS_DIVISOR, "Threshold should be smaller than MAX");
        liquidateThreshold[_token] = _newThreshold;
    }

    function setLiquidationFeeUsd(uint256 _liquidationFeeUsd) external onlyOwner {
        require(_liquidationFeeUsd <= MAX_LIQUIDATION_FEE_USD, "LiquidationFeeUsd should be smaller than MAX");
        liquidationFeeUsd = _liquidationFeeUsd;
        emit SetLiquidationFeeUsd(_liquidationFeeUsd);
    }

    function setMarginFeeBasisPoints(address _token, bool _isLong, uint256 _marginFeeBasisPoints) external onlyOwner {
        require(_marginFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "MarginFeeBasisPoints should be smaller than MAX");
        marginFeeBasisPoints[_token][_isLong] = _marginFeeBasisPoints;
        emit SetMarginFeeBasisPoints(_token, _isLong, _marginFeeBasisPoints);
    }

    function setMaxOpenInterestPerAsset(address _token, uint256 _maxAmount) external onlyOwner {
        maxOpenInterestPerAsset[_token] = _maxAmount;
        emit SetMaxOpenInterestPerAsset(_token, _maxAmount);
    }

    function setMaxOpenInterestPerSide(bool _isLong, uint256 _maxAmount) external onlyOwner {
        maxOpenInterestPerSide[_isLong] = _maxAmount;
        emit SetMaxOpenInterestPerSide(_isLong, _maxAmount);
    }

    function setMaxOpenInterestPerUser(uint256 _maxAmount) external onlyOwner {
        maxOpenInterestPerUser = _maxAmount;
        emit SetMaxOpenInterestPerUser(_maxAmount);
    }

    function setReferEnabled(bool _referEnabled) external onlyOwner {
        referEnabled = _referEnabled;
        emit SetReferEnabled(referEnabled);
    }

    function setTriggerGasFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_TRIGGER_GAS_FEE, "TriggerGasFee exceeded max");
        triggerGasFee = _fee;
        emit SetTriggerGasFee(_fee);
    }

    function setEnableConvertRUSD(bool _isEnableConvertRUSD) external onlyOwner {
        isEnableConvertRUSD = _isEnableConvertRUSD;
        emit SetEnableConvertRUSD(_isEnableConvertRUSD);
    }

    function undelegate(address[] memory _delegates) external {
        for (uint256 i = 0; i < _delegates.length; ++i) {
            EnumerableSetUpgradeable.remove(_delegatesByMaster[msg.sender], _delegates[i]);
        }
    }

    function getFeesV2(
        bytes32 _key,
        uint256 _sizeDelta,
        uint256 _loanDelta,
        bool _isApplyTradingFee,
        bool _isApplyBorrowFee,
        bool _isApplyFundingFee
    ) external view override returns (uint256, int256) {
        require(address(positionKeeper) != address(0), "PositionKeeper not initialized");
        Position memory position = positionKeeper.getPosition(_key);
        require(position.owner != address(0) && position.size > 0, "Position notExist");

        return getFees(
            _sizeDelta,
            _loanDelta,
            _isApplyTradingFee,
            _isApplyBorrowFee,
            _isApplyFundingFee,
            position
        );
    }

    function getFees(
        uint256 _sizeDelta,
        uint256 _loanDelta,
        bool _isApplyTradingFee,
        bool _isApplyBorrowFee,
        bool _isApplyFundingFee,
        Position memory _position
    ) public view returns (uint256, int256) {
        uint256 tradingFee = 0;

        if (_isApplyTradingFee) {
            tradingFee = _sizeDelta == 0 ? 0
                : getPositionFee(
                    _position.indexToken,
                    _position.isLong,
                    _sizeDelta
            );
        }

        if (_isApplyBorrowFee && _loanDelta > 0) {
            tradingFee += getBorrowFee(_position.indexToken, _loanDelta, _position.lastIncreasedTime);
        }

        if (tradingFee > 0) {
            tradingFee = getDiscountFee(_position.owner, tradingFee);
        }

        if (_position.previousFee > 0) {
            tradingFee += _position.previousFee;
        }

        int256 fundingFee = 0;
        
        if (_isApplyFundingFee) {
           fundingFee = getFundingFee(_position.indexToken, _position.isLong, _position.size, _position.entryFunding);
        }

        return (tradingFee, fundingFee);
    }

    function getDiscountFee(address _account, uint256 _fee) public view returns (uint256) {
        if (referralSystem != address(0) && _fee > 0) {
            (, uint256 discountPercentage, ) = IReferralSystem(referralSystem).getDiscountable(_account);

            if (discountPercentage >= BASIS_POINTS_DIVISOR) {
                discountPercentage = 0;
            }

            if (discountPercentage > 0) {
                _fee -= _fee * discountPercentage / BASIS_POINTS_DIVISOR;
            }
        }

        return _fee;
    }

    function getDelegates(address _master) external view override returns (address[] memory) {
        return enumerate(_delegatesByMaster[_master]);
    }

    function validatePosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _size,
        uint256 _collateral
    ) external view override {
        if (_size == 0) {
            require(_collateral == 0, "Collateral must not zero");
            return;
        }

        require(_size >= _collateral, "Position size should be greater than collateral");
        require(
            openInterestPerSide[_isLong] + _size <=
                (
                    maxOpenInterestPerSide[_isLong] > 0
                        ? maxOpenInterestPerSide[_isLong]
                        : DEFAULT_MAX_OPEN_INTEREST
                ),
            "MAX OI per side exceeded"
        );
        require(
            openInterestPerAsset[_indexToken] + _size <=
                (
                    maxOpenInterestPerAsset[_indexToken] > 0
                        ? maxOpenInterestPerAsset[_indexToken]
                        : DEFAULT_MAX_OPEN_INTEREST
                ),
            "MAX OI per asset exceeded"
        );
        require(
            openInterestPerUser[_account] + _size <=
                (maxOpenInterestPerUser > 0 ? maxOpenInterestPerUser : DEFAULT_MAX_OPEN_INTEREST),
            "Max OI per user exceeded"
        );
        require(
            openInterestPerAssetPerSide[_indexToken][_isLong] + _size <=
                maxOpenInterestPerAssetPerSide[_indexToken][_isLong],
            "Max OI per asset/size exceeded"
        );
    }

    function enumerate(EnumerableSetUpgradeable.AddressSet storage set) internal view returns (address[] memory) {
        uint256 length = EnumerableSetUpgradeable.length(set);
        address[] memory output = new address[](length);

        for (uint256 i; i < length; ++i) {
            output[i] = EnumerableSetUpgradeable.at(set, i);
        }

        return output;
    }

    function checkDelegation(address _master, address _delegate) public view override returns (bool) {
        return _master == _delegate || EnumerableSetUpgradeable.contains(_delegatesByMaster[_master], _delegate);
    }

    function getPositionFee(
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) public view override returns (uint256) {
        if (_sizeDelta == 0) {
            return 0;
        }

        return (_sizeDelta * marginFeeBasisPoints[_indexToken][_isLong]) / BASIS_POINTS_DIVISOR;
    }

    function isApprovalCollateralToken(address _token) external view override returns (bool) {
        return _isApprovalCollateralToken(_token, false);
    }

    function isApprovalCollateralToken(address _token, bool _raise) external view override returns (bool) {
        return _isApprovalCollateralToken(_token, _raise);
    }

    function _isApprovalCollateralToken(address _token, bool _raise) internal view returns (bool) {
        bool isStableToken = isStable[_token];
        bool isCollateralToken = isCollateral[_token];
        
        if (isStableToken && isCollateralToken) {
            revert("Invalid config, token should only belong to stable or collateral");
        }

        bool isApproval = isStableToken || isCollateralToken;

        if (_raise && !isApproval) {
            revert("Invalid approval token");
        }

        return isApproval;
    }

    function getFeeManager() external override view returns (address) {
        require(feeManager != address(0), "Fee manager not initialized");
        return feeManager;
    }

    function setPriceMovementPercent(uint256 _priceMovementPercent) external onlyOwner {
        priceMovementPercent = _priceMovementPercent;
        emit SetPriceMovementPercent(_priceMovementPercent);
    }

    function getFundingRate(address _indexToken, address _collateralToken) public view override returns (int256) {
        uint256 vaultPoolAmount = vault.poolAmounts(_collateralToken);

        if (vaultPoolAmount == 0) {
            return 0;
        }

        uint256 totalLong = positionKeeper.globalAmounts(_indexToken, true);
        uint256 totalShort = positionKeeper.globalAmounts(_indexToken, false);
        bool isLongOverShort = totalLong >= totalShort;
        uint256 diff = isLongOverShort ? totalLong - totalShort : totalShort - totalLong;
        int256 multiplier = isLongOverShort ? int256(1) : int256(-1);

        uint256 fundingRate = (diff * fundingRateFactor[_indexToken] * basisFundingRateFactor * BASIS_POINTS_DIVISOR) 
            / vaultPoolAmount;

        if (fundingRate > maxFundingRate) {
            fundingRate = maxFundingRate;
        }
        
        return multiplier * int256(fundingRate);
    }

    function getBorrowFee(
        address _indexToken,
        uint256 _loanDelta,
        uint256 _lastIncreasedTime
    ) public view override returns (uint256) {
        if (_loanDelta == 0) {
            return 0;
        }

        uint256 feeFactor = borrowFeeFactor[_indexToken];

        if (feeFactor == 0) {
            feeFactor = defaultBorrowFeeFactor;
        }

        return feeFactor == 0 ? 0 
            : ((block.timestamp - _lastIncreasedTime) * _loanDelta * feeFactor) /
                BASIS_POINTS_DIVISOR /
                1 hours;
    }

    function getFundingFee(
        address _indexToken,
        bool _isLong,
        uint256 _size,
        int256 _fundingIndex
    ) public view override returns (int256) {
        if (_fundingIndex == 0) {
            return 0;
        }

        return
            _isLong
                ? (int256(_size) * (fundingIndex[_indexToken] - _fundingIndex)) / int256(FUNDING_RATE_PRECISION)
                : (int256(_size) * (_fundingIndex - fundingIndex[_indexToken])) / int256(FUNDING_RATE_PRECISION);
    }

    function updateFunding(address _indexToken, address _collateralToken) external override {
        require(msg.sender == address(positionHandler), "Forbidden");

        if (lastFundingTimes[_indexToken] != 0) {
            fundingIndex[_indexToken] += (getFundingRate(_indexToken, _collateralToken) 
                * int256(block.timestamp - lastFundingTimes[_indexToken])) / int256(1 hours);

            emit UpdateFunding(_indexToken, fundingIndex[_indexToken]);
        }

        lastFundingTimes[_indexToken] = block.timestamp;
    }

    function setBorrowFeeFactor(address _indexToken, uint256 _borrowFeeFactor) external onlyOwner {
        borrowFeeFactor[_indexToken] = _borrowFeeFactor;
        emit SetBorrowFeeFactor(_indexToken, _borrowFeeFactor);
    }

    /*
    @dev: Validate collateral path and return shouldSwap
    */
    function validateCollateralPathAndCheckSwap(address[] memory _path) external override view returns (bool) {
        require(_path.length > 1, "Invalid path length");
        //Trading token index start from 1
        address[] memory collateralPath = _extractCollateralPath(_path, 1);
        uint256 collateralPathLength = collateralPath.length;

        if (isEnableNonStableCollateral) {
            require(collateralPathLength == 1, "Invalid collateral path length, must be 1");
            _isApprovalCollateralToken(collateralPath[0], true);
            return false;
        } else {
            require(collateralPathLength >= 1, "Invalid collateral path length");
            require(isStable[collateralPath[collateralPathLength - 1]], "Last collateral path must be stable");

            if (collateralPathLength > 1 && !isCollateral[collateralPath[0]]) {
                revert("First collateral path must be collateral");
            }

            return collateralPath.length > 1;
        }
    }

    function _extractCollateralPath(address[] memory _path, uint256 _startIndex) internal pure returns (address[] memory) {
        require(_path.length > 1 && _path.length <= 3, "Invalid path length");
        address[] memory newPath;

        if (_path.length == 2 && _startIndex == 1) {
            newPath = new address[](1);
            newPath[0] = _path[1];
            return newPath;
        }

        require(_startIndex < _path.length - 1, "Invalid start index");
        newPath = new address[](_path.length - _startIndex);
        uint256 count = 0;

        for (uint256 i = _startIndex; i < _path.length; i++) {
            newPath[count] = _path[i];
            count++;
        }

        return newPath;
    }

    function _setMaxFundingRate(uint256 _maxFundingRate) internal {
        require(_maxFundingRate < FUNDING_RATE_PRECISION, "Invalid maxFundingRate");
        maxFundingRate = _maxFundingRate;
        emit SetMaxFundingRate(_maxFundingRate);
    }

    function setMaxTriggerPriceLength(uint256 _maxTriggerPriceLength) external onlyOwner {
        require(_maxTriggerPriceLength > 0, "Invalid maxTriggerPriceLength");
        maxTriggerPriceLength = _maxTriggerPriceLength;
        emit SetMaxTriggerPriceLength(_maxTriggerPriceLength);
    }
}
