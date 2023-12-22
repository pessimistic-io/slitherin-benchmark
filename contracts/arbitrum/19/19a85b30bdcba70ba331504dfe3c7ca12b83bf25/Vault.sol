// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

//import "hardhat/console.sol";
import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./EnumerableMap.sol";

import "./IUniswapV2Pair.sol";
import "./IUniswapV3Pool.sol";
import "./IMintable.sol";
import "./IPositionHandler.sol";
import "./ISwapRouter.sol";
import "./IPriceManager.sol";
import "./ISettingsManager.sol";
import "./IVault.sol";

import {Constants} from "./Constants.sol";
import {OrderStatus, OrderType, ConvertOrder, SwapRequest} from "./Structs.sol";

contract Vault is Constants, ReentrancyGuard, Ownable, IVault {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using SafeERC20 for IERC20;

    EnumerableMap.AddressToUintMap private balances;

    uint256 public totalUSD;
    uint256 public totalROLP;
    address public immutable ROLP;
    address public immutable RUSD;

    IPositionHandler public positionHandler;
    IPriceManager public priceManager;
    ISettingsManager public settingsManager;
    ISwapRouter public swapRouter;
    address public positionRouter;
    address public converter;

    mapping(address => uint256) public lastStakedAt;
    bool public isInitialized;

    event TakeAssetIn(
        address indexed account, 
        address indexed refer, 
        uint256 amount, 
        uint256 fee, 
        address token
    );

    event TakeAssetOut(
        address indexed account, 
        address indexed refer, 
        uint256 amount, 
        uint256 fee, 
        uint256 usdOut, 
        address indexToken, 
        uint256 tokenPrice, 
        bool isDebt
    );

    event TransferBounty(address indexed account, uint256 amount, address token, bool isDebt);
    event Stake(address indexed account, address token, uint256 amount, uint256 mintAmount);
    event Unstake(address indexed account, address token, uint256 rolpAmount, uint256 amountOut);
    event SetPositionHandler(address positionHandler);
    event SetPositionRouter(address positionRouter);
    event SetSwapRouter(address swapRouter);
    event SetConverter(address converter);
    event RescueERC20(address indexed recipient, address indexed token, uint256 amount);
    event ConvertRUSD(address indexed recipient, address indexed token, uint256 amountIn, uint256 amountOut);

    modifier hasAccess() {
        require(_isInternal(), "Forbidden");
        _;
    }

    modifier preventTradeForForexCloseTime(address _token) {
        if (priceManager.isForex(_token)) {
            require(!settingsManager.pauseForexForCloseTime() , "Prevent trade for forex close time");
        }
        _;
    }

    constructor(address _ROLP, address _RUSD) {
        _transferOwnership(msg.sender);
        ROLP = _ROLP;
        RUSD = _RUSD;
    }

    //Config functions
    function _isInternal() internal view returns (bool) {
        return msg.sender == address(positionHandler) 
            || msg.sender == address(swapRouter)
            || msg.sender == positionRouter;
    }

    function setPositionRouter(address _positionRouter) external onlyOwner {
        require(Address.isContract(_positionRouter), "Invalid positionRouter");
        positionRouter = _positionRouter;
        emit SetPositionRouter(_positionRouter);
    }

    function setSwapRouter(address _swapRouter) external onlyOwner {
        require(Address.isContract(_swapRouter), "Invalid swapRouter");
        swapRouter = ISwapRouter(_swapRouter);
    }

    function setConverter(address _converter) external onlyOwner {
        converter = _converter;
        emit SetConverter(_converter);
    }
    //End config functions

    function accountDeltaAndFeeIntoTotalBalance(
        bool _hasProfit,
        uint256 _adjustDelta,
        uint256 _fee,
        address _token
    ) external override hasAccess {
        _accountDeltaAndFeeIntoTotalBalance(_hasProfit, _adjustDelta, _fee, _token);
    }

    function distributeFee(address _account, address _refer, uint256 _fee, address _token) external override hasAccess {
        _distributeFee(_account, _refer, _fee, _token);
    }

    function setVaultSettings(
        IPriceManager _priceManager,
        ISettingsManager _settingsManager
    ) external onlyOwner {
        require(!isInitialized, "Not initialized");
        require(Address.isContract(address(_priceManager)), "Invalid PriceManager");
        require(Address.isContract(address(_settingsManager)), "Invalid SettingsManager");
        priceManager = _priceManager;
        settingsManager = _settingsManager;
        isInitialized = true;
    }

    function setPositionHandler(address _positionHandler) external onlyOwner {
        require(Address.isContract(_positionHandler), "Invalid positionHandler");
        positionHandler = IPositionHandler(_positionHandler);
        emit SetPositionHandler(_positionHandler);
    }

    function takeAssetIn(
        address _account, 
        address _refer, 
        uint256 _amount, 
        uint256 _fee, 
        address _token
    ) external override hasAccess {
        require(_amount > 0, "Nothing to take");

        if (_token == RUSD) {
            IMintable(RUSD).burn(_account, _amount);
        } else {
            _transferFrom(_token, _account, _amount);
        }

        uint256 amountInUSD = priceManager.fromTokenToUSD(_token, _amount);
        uint256 feeInUSD = priceManager.fromTokenToUSD(_token, _fee);
        _collectVaultFee(true, amountInUSD, feeInUSD, _refer);
        emit TakeAssetIn(_account, _refer, _amount, _fee, _token);
    }

    function takeAssetOut(
        address _account, 
        address _refer, 
        uint256 _fee, 
        uint256 _usdOut, 
        address _token, 
        uint256 _tokenPrice
    ) external override hasAccess {
        bool isDebt = _takeAssetOut(
            _account, 
            _refer, 
            _fee, 
            _usdOut, 
            _token, 
            _tokenPrice,
            false
        );

        if (_fee > 0) {
            _accountDeltaAndFeeIntoTotalBalance(true, 0, _fee, _token);
        }

        emit TakeAssetOut(_account, _refer, _usdOut, _fee, _usdOut, _token, _tokenPrice, isDebt);
    }

    function transferBounty(address _account, uint256 _amount, address _token, uint256 _tokenPrice) external override hasAccess {
        bool isDebt = _takeAssetOut(
            _account, 
            address(0), 
            0, 
            _amount, 
            _token, 
            _tokenPrice,
            true
        );

        emit TransferBounty(_account, _amount, _token, isDebt);
    }

    function _takeAssetOut(
        address _account, 
        address _refer, 
        uint256 _fee, 
        uint256 _usdOut, 
        address _token, 
        uint256 _tokenPrice, 
        bool _isTransferBounty
    ) internal returns (bool) {
        uint256 usdOutAfterFee = _usdOut - _fee;
        uint256 exactAmountOut = _tokenPrice == PRICE_PRECISION || _token == RUSD
            ? usdOutAfterFee 
            : usdOutAfterFee / _tokenPrice / PRICE_PRECISION;
        bool isDebt = IERC20(_token).balanceOf(address(this)) < exactAmountOut;

        if (isDebt || _token == RUSD) {
            IMintable(RUSD).mint(_account, usdOutAfterFee);

            if (_isTransferBounty) {
                IMintable(RUSD).burn(address(this), usdOutAfterFee);
                totalUSD -= usdOutAfterFee;
            } else {
                _collectVaultFee(false, usdOutAfterFee, _fee, _refer);
            }
        } else {
            _transferTo(_token, exactAmountOut, _account);

            if (_isTransferBounty) {
                uint256 decreaseAmount = (_usdOut * (10**_getTokenDecimals(_token))) / _tokenPrice;
                _decreaseBalance(balances, _token, decreaseAmount);
                totalUSD -= usdOutAfterFee;
            } else {
                _collectVaultFee(false, usdOutAfterFee, _fee, _refer);
            }
        }

        return isDebt && _token != RUSD;
    }

    function _transferFrom(address _token, address _account, uint256 _amount) internal {
        IERC20(_token).safeTransferFrom(_account, address(this), _amount);
    }

    function _transferTo(address _token, uint256 _amount, address _receiver) internal {
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    function _accountDeltaAndFeeIntoTotalBalance(
        bool _hasProfit, 
        uint256 _adjustDelta, 
        uint256 _fee,
        address _token
    ) internal {
        if (_adjustDelta != 0) {
            uint256 feeRewardOnDelta = (_adjustDelta * settingsManager.feeRewardBasisPoints()) / BASIS_POINTS_DIVISOR;
            uint256 feeRewardOnDeltaInToken = priceManager.fromUSDToToken(_token, feeRewardOnDelta);
            
            if (_hasProfit) {
                totalUSD += feeRewardOnDelta;
                _increaseBalance(balances, _token, feeRewardOnDeltaInToken);
            } else {
                bool isVaultUSDExceeded = totalUSD < feeRewardOnDelta;

                if (isVaultUSDExceeded && !settingsManager.isOnBeta()) {
                    revert("Vault USD exceeded");
                } 
                
                if (!isVaultUSDExceeded) {
                    totalUSD -= feeRewardOnDelta;
                } 

                _decreaseBalance(balances, _token, feeRewardOnDeltaInToken);
            }
        }

        if (_fee > 0) {
            uint256 splitFee = _fee * settingsManager.feeRewardBasisPoints() / BASIS_POINTS_DIVISOR;
            totalUSD += splitFee;
            _increaseBalance(balances, _token, priceManager.fromUSDToToken(_token, splitFee));
        }
    }

    function _distributeFee(address _account, address _refer, uint256 _fee, address _token) internal {
        _collectVaultFee(true, _fee, _fee, _refer);

        if (_fee > 0) {
            emit TakeAssetIn(_account, _refer, 0, _fee, _token);
        }
    }

    function _collectVaultFee(
        bool _mint, 
        uint256 _amount, 
        uint256 _fee, 
        address _refer
    ) internal {
        address _feeManager = settingsManager.feeManager();

        if (_fee != 0 && _feeManager != ZERO_ADDRESS) {
            uint256 feeReward = _fee == 0 ? 0 : (_fee * settingsManager.feeRewardBasisPoints()) / BASIS_POINTS_DIVISOR;
            uint256 feeMinusFeeReward = _fee - feeReward;
            IMintable(RUSD).mint(_feeManager, feeMinusFeeReward);

            if (_mint) {
                _amount -= feeMinusFeeReward;
            } else {
                _amount += feeMinusFeeReward;
            }

            _fee = feeReward;
        }

        if (_refer != ZERO_ADDRESS && settingsManager.referEnabled()) {
            uint256 referFee = (_fee * settingsManager.referFee()) / BASIS_POINTS_DIVISOR;
            IMintable(RUSD).mint(_refer, referFee);

            if (_mint) {
                _amount -= referFee;
            } else {
                _amount += referFee;
            }
        }

        if (_amount > 0) {
            if (_mint) {
                IMintable(RUSD).mint(address(this), _amount);
            } else {
                IMintable(RUSD).burn(address(this), _amount);
            }
        }
    }

    function getROLPPrice() external view returns (uint256) {
        return _getROLPPrice();
    }

    function _getROLPPrice() internal view returns (uint256) {
        if (totalROLP == 0) {
            return DEFAULT_ROLP_PRICE;
        } else {
            return (BASIS_POINTS_DIVISOR * (10 ** ROLP_DECIMALS) * totalUSD) / (totalROLP * PRICE_PRECISION);
        }
    }

    function updateTotalROLP() external {
        require(_isInternal() || msg.sender == owner(), "Forbidden");
        totalROLP = IERC20(ROLP).totalSupply();
    }

    function updateBalance(address _token) external {
        require(_isInternal() || msg.sender == owner(), "Forbidden");
        balances.set(_token, IERC20(_token).balanceOf(address(this)));
    }

    function updateBalances() external {
        require(_isInternal() || msg.sender == owner(), "Forbidden");
        uint256 sum;

        for (uint256 i = 0; i < balances.length(); i++) {
            (address token, ) = balances.at(i);

            if (token != address(0) && Address.isContract(token)) {
                uint256 balance = IERC20(token).balanceOf(address(this));
                balances.set(token, balance);
                sum += priceManager.fromTokenToUSD(token, balance);
            }
        }

        totalUSD = sum;
    }

    function stake(address _account, address _token, uint256 _amount) external nonReentrant {
        require(settingsManager.isStaking(_token), "This token not allowed for staking");
        require(
            (settingsManager.checkDelegation(_account, msg.sender)) && _amount > 0,
            "Zero amount or not allowed for stakeFor"
        );
        uint256 usdAmount = priceManager.fromTokenToUSD(_token, _amount);
        _transferFrom(_token, _account, _amount);
        uint256 usdAmountFee = (usdAmount * settingsManager.stakingFee()) / BASIS_POINTS_DIVISOR;
        uint256 usdAmountAfterFee = usdAmount - usdAmountFee;
        uint256 mintAmount;

        if (totalROLP == 0) {
            mintAmount =
                (usdAmountAfterFee * DEFAULT_ROLP_PRICE * (10 ** ROLP_DECIMALS)) /
                (PRICE_PRECISION * BASIS_POINTS_DIVISOR);
        } else {
            mintAmount = (usdAmountAfterFee * totalROLP) / totalUSD;
        }

        _accountDeltaAndFeeIntoTotalBalance(true, 0, usdAmountFee, _token);
        _distributeFee(_account, ZERO_ADDRESS, usdAmountFee, _token);
        require(mintAmount > 0, "Staking amount too low");
        IMintable(ROLP).mint(_account, mintAmount);
        lastStakedAt[_account] = block.timestamp;
        totalROLP += mintAmount;
        totalUSD += usdAmountAfterFee;
        _increaseBalance(balances, _token, priceManager.fromUSDToToken(_token, usdAmountAfterFee));
        emit Stake(_account, _token, _amount, mintAmount);
    }

    function unstake(address _tokenOut, uint256 _rolpAmount, address _receiver) external nonReentrant {
        require(_isApprovalToken(_tokenOut), "Invalid tokenOut");
        require(_rolpAmount > 0 && _rolpAmount <= totalROLP, "Zero amount not allowed and cant exceed total ROLP");
        require(
            lastStakedAt[msg.sender] + settingsManager.cooldownDuration() <= block.timestamp,
            "Cooldown duration not yet passed"
        );
        require(settingsManager.isEnableUnstaking(), "Not enable unstaking");

        IMintable(ROLP).burn(msg.sender, _rolpAmount);
        uint256 usdAmount = (_rolpAmount * totalUSD) / totalROLP;
        totalROLP -= _rolpAmount;
        uint256 usdAmountFee = (usdAmount * settingsManager.unstakingFee()) / BASIS_POINTS_DIVISOR;
        uint256 usdAmountAfterFee = usdAmount - usdAmountFee;
        totalUSD -= usdAmount;
        uint256 amountOutInToken = _tokenOut == RUSD ? usdAmount: priceManager.fromUSDToToken(_tokenOut, usdAmountAfterFee);
        require(amountOutInToken > 0, "Unstaking amount too low");
        _decreaseBalance(balances, _tokenOut, amountOutInToken);
        _accountDeltaAndFeeIntoTotalBalance(true, 0, usdAmountFee, _tokenOut);
        _distributeFee(msg.sender, ZERO_ADDRESS, usdAmountFee, _tokenOut);
        require(IERC20(_tokenOut).balanceOf(address(this)) >= amountOutInToken, "Insufficient");
        _transferTo(_tokenOut, amountOutInToken, _receiver);
        emit Unstake(msg.sender, _tokenOut, _rolpAmount, amountOutInToken);
    }

    function rescueERC20(address _recipient, address _token, uint256 _amount) external onlyOwner {
        bool isVaultBalance = balances.get(_token) > 0;
        require(IERC20(_token).balanceOf(address(this)) >= _amount, "Insufficient rescue amount");
        IERC20(_token).safeTransfer(_recipient, _amount);

        if (isVaultBalance) {
            uint256 rescueAmountInUSD = priceManager.fromTokenToUSD(_token, _amount);
            totalUSD -= rescueAmountInUSD;
            _decreaseBalance(balances, _token, priceManager.fromUSDToToken(_token, rescueAmountInUSD));
        }

        emit RescueERC20(_recipient, _token, _amount);
    }

    function convertRUSD(
        address _account,
        address _recipient, 
        address _tokenOut, 
        uint256 _amount
    ) external nonReentrant {
        require(msg.sender == converter, "Forbidden: Not converter");
        require(_isApprovalToken(_tokenOut), "Invalid tokenOut");
        require(settingsManager.isEnableConvertRUSD(), "Convert RUSD temporarily disabled");
        require(IERC20(RUSD).balanceOf(_account) >= _amount, "Insufficient RUSD to convert");
        IMintable(RUSD).burn(_account, _amount);
        uint256 amountOut = priceManager.fromUSDToToken(_tokenOut, _amount);
        require(IERC20(_tokenOut).balanceOf(address(this)) >= amountOut, "Insufficient amountOut");
        totalUSD -= _amount;
        _decreaseBalance(balances, _tokenOut, amountOut);
        IERC20(_tokenOut).safeTransfer(_recipient, amountOut);
        emit ConvertRUSD(_recipient, _tokenOut, _amount, amountOut);
    }

    function emergencyDeposit(address _token, uint256 _amount) external {
        require(_isApprovalToken(_token), "Invalid deposit token");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 amountInUSD = priceManager.fromTokenToUSD(_token, _amount);
        totalUSD += amountInUSD;
        _increaseBalance(balances, _token, priceManager.fromUSDToToken(_token, amountInUSD));
    }

    function getBalances() external view returns (address[] memory, uint256[] memory) {
        return _iterator();
    }

    function getBalance(address _token) external view returns (uint256) {
        return balances.get(_token);
    }

    function _iterator() internal view returns (address[] memory, uint256[] memory) {
        address[] memory tokensArr = new address[](balances.length());
        uint256[] memory balancesArr = new uint256[](balances.length());

        for (uint256 i = 0; i < balances.length(); i++) {
            (address token, uint256 balance) = balances.at(i);
            tokensArr[i] = token;
            balancesArr[i] = balance;
        }

        return (tokensArr, balancesArr);
    }

    function _isApprovalToken(address _token) internal view returns (bool) {
        return settingsManager.isCollateral(_token) || settingsManager.isStable(_token);
    }

    function _increaseBalance(EnumerableMap.AddressToUintMap storage _map, address _token, uint256 _amount) internal {
        _setBalance(_map, _token, _amount, true);
    }

    function _decreaseBalance(EnumerableMap.AddressToUintMap storage _map, address _token, uint256 _amount) internal {
        _setBalance(_map, _token, _amount, false);
    }

    function _setBalance(EnumerableMap.AddressToUintMap storage _map, address _token, uint256 _amount, bool _isPlus) internal {
        uint256 prevBalance = _map.contains(_token) ? _map.get(_token) : 0;
        bool isNegativeBalance = !_isPlus && prevBalance < _amount;

        if (isNegativeBalance && !settingsManager.isOnBeta()) {
            revert("Negative balance reached");
        } 
        
        uint256 newBalance;

        if (_isPlus) {
            newBalance = prevBalance + _amount;
        } else if (!_isPlus && !isNegativeBalance) {
            newBalance = prevBalance - _amount;
        }

        if (newBalance > 0) {
            _map.set(_token, newBalance);
        }
    }

    function _getTokenDecimals(address _token) internal view returns(uint256) {
        uint256 tokenDecimals = priceManager.tokenDecimals(_token);
        require(tokenDecimals > 0, "Invalid tokenDecimals");
        return tokenDecimals;
    }

    //These function for test, will remove after deploying on main net
    function setInitializedForDev(bool _isInitialized) external onlyOwner {
       isInitialized = _isInitialized;
    }
}
