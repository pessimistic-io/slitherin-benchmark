// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

//UUPS proxy lib
import "./UUPSUpgradeable.sol";

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./EnumerableMapUpgradeable.sol";

import "./IROLP.sol";
import "./IMintable.sol";
import "./IBurnable.sol";
import "./IPriceManager.sol";
import "./IReferralSystemV2.sol";
import "./ISettingsManagerV2.sol";
import "./IPositionKeeperV2.sol";
import "./IVaultV2.sol";

import {Constants} from "./Constants.sol";
import {OrderStatus, OrderType, ConvertOrder, SwapRequest} from "./Structs.sol";

contract VaultV2_NoRef is IVaultV2, Constants, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using EnumerableMapUpgradeable for EnumerableMapUpgradeable.AddressToUintMap;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    EnumerableSetUpgradeable.AddressSet private collateralTokens;
    EnumerableSetUpgradeable.AddressSet private tradingTokens;
    mapping(address => uint256) private tokenBalances;

    uint256 public aumAddition;
    uint256 public aumDeduction;
    address public ROLP;
    address public RUSD;

    IPriceManager public priceManager;
    ISettingsManagerV2 public settingsManager;
    IPositionKeeperV2 public positionKeeper;
    address public positionHandler;
    address public referralSystem;
    address public swapRouter;
    address public positionRouter;
    address public converter;
    address public vaultUtils;

    mapping(address => uint256) public override stakeAmounts;
    mapping(address => uint256) public override poolAmounts;
    mapping(address => uint256) public override reservedAmounts;
    mapping(address => uint256) public override guaranteedAmounts;
    mapping(bytes32 => mapping(uint256 => VaultBond)) public bonds;
    uint256[50] private __gap;

    event UpdatePoolAmount(address indexed token, uint256 amount, uint256 current, bool isPlus);
    event UpdateReservedAmount(address indexed token, uint256 amount, uint256 current, bool isPlus);
    event UpdateGuaranteedAmount(address indexed token, uint256 amount, uint256 current, bool isPlus);

    event DistributeFee(
        bytes32 key,
        address account,
        address refer,
        uint256 fee
    );

    event TakeAssetIn(
        bytes32 key,
        uint256 txType,
        address indexed account, 
        address indexed token,
        uint256 amount,
        uint256 amountInUSD
    );

    event TakeAssetOut(
        bytes32 key,
        address indexed account, 
        address indexed refer, 
        uint256 usdOut, 
        uint256 fee, 
        address token, 
        uint256 tokenAmountOut,
        uint256 tokenPrice
    );

    event TakeAssetBack(
        address indexed account, 
        uint256 amount,
        address token,
        bytes32 key,
        uint256 txType
    );

    event ReduceBond(
        address indexed account, 
        uint256 amount,
        address token,
        bytes32 key,
        uint256 txType
    );

    event TransferBounty(address indexed account, uint256 amount);
    event Stake(address indexed account, address token, uint256 amount, uint256 mintAmount);
    event Unstake(address indexed account, address token, uint256 rolpAmount, uint256 amountOut);
    event FinalInitialized(
        address ROLP, 
        address RUSD, 
        address priceManager, 
        address settingsManager,
        address positionRouter,
        address positionHandler,
        address positionKeeper,
        address vaultUtils
    );
    event SetSwapRouter(address swapRouter);
    event SetConverter(address converter);
    event RescueERC20(address indexed recipient, address indexed token, uint256 amount);
    event ConvertRUSD(address indexed recipient, address indexed token, uint256 amountIn, uint256 amountOut);
    event SetRefferalSystem(address referralSystem);

    function initialize(
        address _ROLP, 
        address _RUSD
    ) public reinitializer(7) {
        __Ownable_init();
        ROLP = _ROLP;
        RUSD = _RUSD;
    }

    function finalInitialize(
        address _priceManager, 
        address _settingsManager,
        address _positionRouter,
        address _positionHandler,
        address _positionKeeper,
        address _vaultUtils
    ) public onlyOwner {
        require(AddressUpgradeable.isContract(_priceManager)
            && AddressUpgradeable.isContract(_settingsManager)
            && AddressUpgradeable.isContract(_positionRouter)
            && AddressUpgradeable.isContract(_positionHandler)
            && AddressUpgradeable.isContract(_positionKeeper)
            && AddressUpgradeable.isContract(_vaultUtils), "IVLCA");
        priceManager = IPriceManager(_priceManager);
        settingsManager = ISettingsManagerV2(_settingsManager);
        positionRouter = _positionRouter;
        positionHandler = _positionHandler;
        positionKeeper = IPositionKeeperV2(_positionKeeper);
        vaultUtils = _vaultUtils;
        emit FinalInitialized(
            ROLP, 
            RUSD, 
            _priceManager, 
            _settingsManager,
            _positionRouter,
            _positionHandler,
            _positionKeeper,
            _vaultUtils
        );
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    //Config functions
    function setSwapRouter(address _swapRouter) external onlyOwner {
        require(AddressUpgradeable.isContract(_swapRouter), "Invalid swapRouter");
        swapRouter = _swapRouter;
    }

    function setConverter(address _converter) external onlyOwner {
        converter = _converter;
        emit SetConverter(_converter);
    }

    function setAumAdjustment(uint256 _aumAddition, uint256 _aumDeduction) external onlyOwner {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }

    function addOrRemoveCollateralToken(address _token, bool _isAdd) external onlyOwner {
        if (_isAdd) {
            require(!collateralTokens.contains(_token), "Existed");
            collateralTokens.add(_token);
        } else {
            require(collateralTokens.contains(_token), "Not exist");
            collateralTokens.remove(_token);
        }
    }

    function addOrRemoveTradingToken(address _token, bool _isAdd) external onlyOwner {
        if (_isAdd) {
            require(!tradingTokens.contains(_token), "Existed");
            tradingTokens.add(_token);
        } else {
            require(tradingTokens.contains(_token), "Not exist");
            tradingTokens.remove(_token);
        }
    }

    function getCollateralTokens() external view returns (address[] memory) {
        address[] memory tokens = new address[](collateralTokens.length());

        for (uint256 i = 0; i < collateralTokens.length(); i++) {
            tokens[i] = collateralTokens.at(i);
        }

        return tokens;
    }

    function getTradingTokens() external view returns (address[] memory) {
        address[] memory tokens = new address[](tradingTokens.length());

        for (uint256 i = 0; i < tradingTokens.length(); i++) {
            tokens[i] = tradingTokens.at(i);
        }

        return tokens;
    }

    function setRefferalSystem(address _refferalSystem) external onlyOwner {
        referralSystem = _refferalSystem;
        emit SetRefferalSystem(_refferalSystem);
    }
    //End config functions

    function increasePoolAmount(address _collateralToken, uint256 _amount) public override {
        _isVaultUpdater(msg.sender, true);
        _increasePoolAmount(_collateralToken, _amount);
    }

    function _increasePoolAmount(address _collateralToken, uint256 _amount) internal {
        if (!collateralTokens.contains(_collateralToken)) {
            collateralTokens.add(_collateralToken);
        }

        _updatePoolAmount(_collateralToken, _amount, true);
    }

    function decreasePoolAmount(address _collateralToken, uint256 _amount) public override {
        _isVaultUpdater(msg.sender, true);
        _decreasePoolAmount(_collateralToken, _amount);
    }

    function _decreasePoolAmount(address _collateralToken, uint256 _amount) internal {
        _updatePoolAmount(_collateralToken, _amount, false);
    }

    function _updatePoolAmount(address _collateralToken, uint256 _amount, bool _isPlus) internal {
        if (_isPlus) {
            poolAmounts[_collateralToken] += _amount;
        } else {
            require(poolAmounts[_collateralToken] >= _amount, "Vault: poolAmount exceeded");
            poolAmounts[_collateralToken] -= _amount;
        }

        emit UpdatePoolAmount(_collateralToken, _amount, poolAmounts[_collateralToken], _isPlus);
    }

    function increaseReservedAmount(address _token, uint256 _amount) external override {
        _isVaultUpdater(msg.sender, true);
        _updateReservedAmount(_token, _amount, true);
    }

    function decreaseReservedAmount(address _token, uint256 _amount) external override {
        _isVaultUpdater(msg.sender, true);
        _updateReservedAmount(_token, _amount, false);
    }

    function _updateReservedAmount(address _token, uint256 _amount, bool _isPlus) internal {
        if (_isPlus) {
            reservedAmounts[_token] += _amount;
        } else {
            require(reservedAmounts[_token] >= _amount, "Vault: reservedAmount exceeded");
            reservedAmounts[_token] -= _amount;
        }

        emit UpdateReservedAmount(_token, _amount, reservedAmounts[_token], _isPlus);
    }

    function increaseGuaranteedAmount(address _token, uint256 _amount) external override {
        _isVaultUpdater(msg.sender, true);
        _updateGuaranteedAmount(_token, _amount, true);
    }

    function decreaseGuaranteedAmount(address _token, uint256 _amount) external override {
        _isVaultUpdater(msg.sender, true);
        _updateGuaranteedAmount(_token, _amount, false);
    }

    function _updateGuaranteedAmount(address _token, uint256 _amount, bool _isPlus) internal {
        if (_isPlus) {
            guaranteedAmounts[_token] += _amount;
        } else {
            require(guaranteedAmounts[_token] >= _amount, "Vault: guaranteedAmounts exceeded");
            guaranteedAmounts[_token] -= _amount;
        }

        emit UpdateGuaranteedAmount(_token, _amount, guaranteedAmounts[_token], _isPlus);
    }

    function takeAssetIn(
        address _account, 
        uint256 _amount, 
        address _token,
        bytes32 _key,
        uint256 _txType
    ) external override {
        require(msg.sender == positionRouter || msg.sender == address(swapRouter), "FBD: Not routers");
        require(_amount > 0 && _token != address(0), "Invalid amount or token");
        settingsManager.isApprovalCollateralToken(_token, true);

        if (_token == RUSD) {
            IBurnable(RUSD).burn(_account, _amount);
        } else {
            _transferFrom(_token, _account, _amount);
        }

        uint256 amountInUSD = _token == RUSD ? _amount: priceManager.fromTokenToUSD(_token, _amount);
        require(amountInUSD > 0, "Invalid amountInUSD");
        
        bonds[_key][_txType].token = _token;
        bonds[_key][_txType].amount += _amount;
        bonds[_key][_txType].owner = _account;
        _increaseTokenBalances(_token, _amount);
        emit TakeAssetIn(_key, _txType, _account, _token, _amount, amountInUSD);
    }

    function takeAssetOut(
        bytes32 _key,
        address _account, 
        uint256 _fee, 
        uint256 _usdOut, 
        address _token, 
        uint256 _tokenPrice
    ) external override {
        require(msg.sender == positionHandler || msg.sender == swapRouter, "Forbidden");
        //Implement rebate on next upgrade
        address feeManager = settingsManager.feeManager();
        address refer = feeManager;
        uint256 rebatePercentage = BASIS_POINTS_DIVISOR;

        uint256 tokenAmountOut = _takeAssetOut(
            _account, 
            refer, 
            _fee,
            rebatePercentage,
            _usdOut, 
            _token, 
            _tokenPrice,
            feeManager
        );
        emit TakeAssetOut(
            _key, 
            _account, 
            refer, 
            _usdOut, 
            _fee, 
            _token, 
            tokenAmountOut, 
            _tokenPrice
        );
    }

    function _takeAssetOut(
        address _account, 
        address _refer,
        uint256 _fee, 
        uint256 _rebatePercentage,
        uint256 _usdOut, 
        address _token, 
        uint256 _tokenPrice,
        address _feeManager
    ) internal returns (uint256) {
        require(_token != address(0) && _tokenPrice > 0, "Invalid asset");
        uint256 usdOutAfterFee = _usdOut == 0 ? 0 : _usdOut - _fee;
        //Force convert 1-1 if stable
        uint256 tokenPrice = settingsManager.isStable(_token) ? PRICE_PRECISION : _tokenPrice;
        uint256 tokenAmountOut = usdOutAfterFee == 0 ? 0 : priceManager.fromUSDToToken(_token, usdOutAfterFee, tokenPrice);
        _transferTo(_token, tokenAmountOut, _account);
        _decreaseTokenBalances(_token, tokenAmountOut);
        _collectFee(_fee, _refer, _rebatePercentage, _feeManager, false);

        return tokenAmountOut;
    }

    function takeAssetBack(
        address _account, 
        bytes32 _key,
        uint256 _txType
    ) external override {
        require(_isPosition(), "FBD");
        VaultBond memory bond = bonds[_key][_txType];

        if (bond.owner == _account && bond.amount >= 0 && bond.token != address(0)) {
            _decreaseBond(_key, _account, _txType, bond.amount, true);
            _decreaseTokenBalances(bond.token, bond.amount);
            _transferTo(bond.token, bond.amount, _account);
            emit TakeAssetBack(_account, bond.amount, bond.token, _key, _txType);
        }
    }

    function decreaseBond(bytes32 _key, address _account, uint256 _txType) external {
        require(msg.sender == address(positionHandler) || msg.sender == swapRouter, "FBD");
        _decreaseBond(_key, _account, _txType, bonds[_key][_txType].amount, false);
    }

    function _decreaseBond(bytes32 _key, address _account, uint256 _txType, uint256 _decAmount, bool _isTakeAssetBack) internal {
        VaultBond storage bond = bonds[_key][_txType];
        address owner = bond.owner;
        address token = bond.token;

        require(bond.token != address(0) && bond.owner != address(0) && bond.owner == _account 
            && bond.amount > 0 && _decAmount <= bond.amount, "Invalid bond");

        if (_decAmount == bond.amount) {
            bond.owner = address(0);
            bond.token = address(0);
        }

        bond.amount -= _decAmount;

        if (_txType == CREATE_POSITION_STOP_LIMIT && !_isTakeAssetBack) {
            bonds[_key][CREATE_POSITION_LIMIT] = VaultBond({owner: owner, token: token, amount: _decAmount});
        }
    }

    function transferBounty(address _account, uint256 _amount) external override {
        require(_isInternal(), "FBD");

        if (_account != address(0) && _amount > 0) {
            IMintable(RUSD).mint(_account, _amount);
            emit TransferBounty(_account, _amount);
        }
    }

    function _transferFrom(address _token, address _account, uint256 _amount) internal {
        IERC20Upgradeable(_token).safeTransferFrom(_account, address(this), _amount);
    }

    function _transferTo(address _token, uint256 _amount, address _receiver) internal {
        if (_receiver != address(0) && _amount > 0) {
            uint256 minimumVaultReserve = settingsManager.minimumVaultReserves(_token);

            if (minimumVaultReserve > 0) {
                require(IERC20Upgradeable(_token).balanceOf(address(this)) - _amount 
                    >= minimumVaultReserve, "MinVaultReserve exceeded");
            }

            IERC20Upgradeable(_token).safeTransfer(_receiver, _amount);
        }
    }

    function getROLPPrice() external view returns (uint256) {
        return _getROLPPrice();
    }

    function _getROLPPrice() internal view returns (uint256) {
        uint256 totalRolp = totalROLP();

        if (totalRolp == 0) {
            return DEFAULT_ROLP_PRICE;
        } else {
            return (BASIS_POINTS_DIVISOR * (10 ** ROLP_DECIMALS) * _getTotalUSD()) / (totalRolp * PRICE_PRECISION);
        }
    }

    function getTotalUSD() external override view returns (uint256) {
        return _getTotalUSD();
    }

    function _getTotalUSD() internal view returns (uint256) {
        uint256 aum = aumAddition;
        uint256 shortProfits;
        uint256 collateralsLength = collateralTokens.length();
        address[] memory whitelistTokens = getWhitelistTokens();

        for (uint256 i = 0; i < whitelistTokens.length; i++) {
            if (i < collateralsLength) {
                aum += poolAmounts[collateralTokens.at(i)];
            } else {
                uint256 j = i - collateralsLength;
                address indexToken = tradingTokens.at(j);
                (bool hasProfit, uint256 delta) = positionKeeper.getGlobalShortDelta(indexToken);

                if (!hasProfit) {
                    // Add losses from shorts
                    aum += delta;
                } else {
                    shortProfits += delta;
                }

                aum += guaranteedAmounts[indexToken];
                aum = aum + poolAmounts[indexToken] - reservedAmounts[indexToken];
            }
        }


        aum = shortProfits > aum ? 0 : aum - shortProfits;
        return (aumDeduction > aum ? 0 : aum - aumDeduction) + tokenBalances[RUSD];
    }

    function getWhitelistTokens() public view returns (address[] memory) {
        address[] memory whitelistTokens = new address[](collateralTokens.length() + tradingTokens.length());
        uint256 count = 0;

        for (uint256 i = 0; i < collateralTokens.length(); i++) {
            whitelistTokens[count] = collateralTokens.at(i);
            count++;
        }

        for (uint256 i = 0; i < tradingTokens.length(); i++) {
            whitelistTokens[count] = tradingTokens.at(i);
            count++;
        }

        return whitelistTokens;
    }

    function updateBalance(address _token) external override {
        require(msg.sender == owner() || msg.sender == swapRouter, "Forbidden");
        tokenBalances[_token] = IERC20Upgradeable(_token).balanceOf(address(this));
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
        uint256 totalRolp = totalROLP();
        uint256 totalUsd = _getTotalUSD();

        if (totalRolp == 0 || totalUsd == 0) {
            mintAmount =
                (usdAmountAfterFee * DEFAULT_ROLP_PRICE * (10 ** ROLP_DECIMALS)) /
                (PRICE_PRECISION * BASIS_POINTS_DIVISOR);
        } else {
            mintAmount = (usdAmountAfterFee * totalRolp) / totalUsd;
        }

        _collectFee(usdAmountFee, ZERO_ADDRESS, 0, address(0), true);
        require(mintAmount > 0, "Staking amount too low");
        IROLP(ROLP).mintWithCooldown(_account, mintAmount, block.timestamp + settingsManager.cooldownDuration());
        _increaseTokenBalances(_token, _amount);
        _increasePoolAmount(_token, usdAmountAfterFee);
        stakeAmounts[_token] += usdAmountAfterFee;
        emit Stake(_account, _token, _amount, mintAmount);
    }

    function unstake(address _tokenOut, uint256 _rolpAmount, address _receiver) external nonReentrant {
        require(settingsManager.isApprovalCollateralToken(_tokenOut), "Invalid approvalToken");
        uint256 totalRolp = totalROLP();
        require(_rolpAmount > 0 && totalRolp > 0 && _rolpAmount <= totalRolp, "Zero amount not allowed and cant exceed total ROLP");
        require(block.timestamp >= IROLP(ROLP).cooldownDurations(msg.sender), "Cooldown duration not yet passed");
        require(settingsManager.isEnableUnstaking(), "Not enable unstaking");

        IBurnable(ROLP).burn(msg.sender, _rolpAmount);
        uint256 usdAmount = (_rolpAmount * _getTotalUSD()) / totalRolp;
        uint256 usdAmountFee = (usdAmount * settingsManager.unstakingFee()) / BASIS_POINTS_DIVISOR;
        uint256 usdAmountAfterFee = usdAmount - usdAmountFee;
        uint256 amountOutInToken = usdAmountAfterFee == 0 ? 0 
            : (_tokenOut == RUSD ? usdAmountAfterFee: priceManager.fromUSDToToken(_tokenOut, usdAmountAfterFee));
        require(amountOutInToken > 0, "Unstaking amount too low");

        _decreaseTokenBalances(_tokenOut, amountOutInToken);
        _decreasePoolAmount(_tokenOut, usdAmountAfterFee);
        _collectFee(usdAmountFee, ZERO_ADDRESS, 0, address(0), true);
        require(IERC20Upgradeable(_tokenOut).balanceOf(address(this)) >= amountOutInToken, "Insufficient");
        _transferTo(_tokenOut, amountOutInToken, _receiver);
        stakeAmounts[_tokenOut] -= usdAmountAfterFee;
        emit Unstake(msg.sender, _tokenOut, _rolpAmount, amountOutInToken);
    }

    function totalROLP() public view returns (uint256) {
        return IERC20Upgradeable(ROLP).totalSupply();
    }

    function totalRUSD() public view returns (uint256) {
        return IERC20Upgradeable(RUSD).totalSupply();
    }

    function distributeFee(bytes32 _key, address _account, uint256 _fee) external override {
        _isPositionHandler(msg.sender, true);
        address feeManager = settingsManager.feeManager();
        _collectFee(_fee, address(0), 0, feeManager, false);

        if (_fee > 0) {
            emit DistributeFee(_key, _account, feeManager, _fee);
        }
    }

    function _collectFee(uint256 _fee, address _refer, uint256 _rebatePercentage, address _feeManager, bool _isStake) internal {
        if (_feeManager == ZERO_ADDRESS) {
            _feeManager = settingsManager.feeManager();
        }
        
        //Pay rebate first
        if (_refer != ZERO_ADDRESS && settingsManager.referEnabled()) {
            uint256 referFee = _rebatePercentage >= BASIS_POINTS_DIVISOR ? _fee : (_fee * _rebatePercentage / BASIS_POINTS_DIVISOR);
            _fee -= referFee;

            if (referFee > 0) {
                IMintable(RUSD).mint(_refer, referFee);
            }
        }

        if (_fee > 0 && _feeManager != ZERO_ADDRESS) {
            //Stake/Unstake will take full fee, otherwise reserve to vault
            uint256 feeReserve = _isStake ? 0 : ((_fee * settingsManager.feeRewardBasisPoints()) / BASIS_POINTS_DIVISOR);
            uint256 systemFee = _fee - feeReserve;
            _fee -= systemFee;

            if (systemFee > 0) {
                IMintable(RUSD).mint(_feeManager, systemFee);
            }
        }

        if (_fee > 0) {
            //Reserve the rest fee for vault
            IMintable(RUSD).mint(address(this), _fee);
            _increaseTokenBalances(RUSD, _fee);
        }
    }

    function rescueERC20(address _recipient, address _token, uint256 _amount) external onlyOwner {
        bool isVaultBalance = tokenBalances[_token] > 0 && _token != RUSD;
        require(IERC20Upgradeable(_token).balanceOf(address(this)) >= _amount, "Insufficient");
        IERC20Upgradeable(_token).safeTransfer(_recipient, _amount);

        if (isVaultBalance) {
            _decreaseTokenBalances(_token, _amount);
        }

        emit RescueERC20(_recipient, _token, _amount);
    }

    function directDeposit(address _token, uint256 _amount) external {
        settingsManager.isApprovalCollateralToken(_token, true);
        require(_amount > 0, "ZERO amount");
        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 amountInUSD = priceManager.fromTokenToUSD(_token, _amount);
        _increaseTokenBalances(_token, _amount);
        _updatePoolAmount(_token, amountInUSD, true);
    }

    function _increaseTokenBalances(address _token, uint256 _amount) internal {
        _setBalance(_token, _amount, true);
    }

    function _decreaseTokenBalances(address _token, uint256 _amount) internal {
        _setBalance(_token, _amount, false);
    }

    function _setBalance(address _token, uint256 _amount, bool _isPlus) internal {
        if (_amount > 0) {
            uint256 prevBalance = tokenBalances[_token];

            if (!_isPlus && prevBalance < _amount) {
                revert("Vault balances exceeded");
            } 
            
            uint256 newBalance = _isPlus ? prevBalance + _amount : prevBalance - _amount;
            tokenBalances[_token] = newBalance;
        }
    }

    function _isInternal() internal view returns (bool) {
        return _isPosition() || _isSwapRouter(msg.sender, false);
    }

    function _isPosition() internal view returns (bool) {
        return _isPositionHandler(msg.sender, false) 
            || _isPositionRouter(msg.sender, false);
    }

    function _isPositionRouter(address _caller, bool _raise) internal view returns (bool) {
        bool res = _caller == address(positionRouter);

        if (_raise && !res) {
            revert("FBD: Not positionRouter");
        }

        return res;
    }

    function _isPositionHandler(address _caller, bool _raise) internal view returns (bool) {
        bool res = _caller == positionHandler;

        if (_raise && !res) {
            revert("FBD: Not positionHandler");
        }

        return res;
    }

    function _isSwapRouter(address _caller, bool _raise) internal view returns (bool) {
        bool res = _caller == address(swapRouter);

        if (_raise && !res) {
            revert("FBD: Not swapRouter");
        }

        return res;
    }

    function _isVaultUpdater(address _caller, bool _raise) internal view returns (bool) {
        bool res = _caller == vaultUtils || _isPositionHandler(_caller, false);

        if (_raise && !res) {
            revert("FBD: Not vaultUpdater");
        }

        return res;
    }

    function getBond(bytes32 _key, uint256 _txType) external view returns (VaultBond memory) {
        return bonds[_key][_txType];
    }

    function getTokenBalance(address _token) external view returns (uint256) {
        return tokenBalances[_token];
    }

    // function getBondOwner(bytes32 _key, uint256 _txType) external override view returns (address) {
    //     return bonds[_key][_txType].owner;
    // }

    // function getBondToken(bytes32 _key, uint256 _txType) external override view returns (address) {
    //     return bonds[_key][_txType].token;
    // }

    // function getBondAmount(bytes32 _key, uint256 _txType) external override view returns (uint256) {
    //     return bonds[_key][_txType].amount;
    // }

    /*
    @dev: Let converter convert RUSD to token, will be disabled when ReferralSystemV2 is ready.
    */
    function convertRUSD(
        address _account,
        address _recipient, 
        address _tokenOut, 
        uint256 _amount
    ) external nonReentrant {
        require(msg.sender == converter, "FBD");
        settingsManager.isApprovalCollateralToken(_tokenOut, true);
        require(settingsManager.isEnableConvertRUSD(), "Convert RUSD temporarily disabled");
        require(_amount > 0 && IERC20Upgradeable(RUSD).balanceOf(_account) >= _amount, "Insufficient RUSD to convert");
        IBurnable(RUSD).burn(_account, _amount);
        uint256 amountOut = settingsManager.isStable(_tokenOut) ? priceManager.fromUSDToToken(_tokenOut, _amount, PRICE_PRECISION) 
                : priceManager.fromUSDToToken(_tokenOut, _amount);
        require(IERC20Upgradeable(_tokenOut).balanceOf(address(this)) >= amountOut, "Insufficient");
        IERC20Upgradeable(_tokenOut).safeTransfer(_recipient, amountOut);
        _decreaseTokenBalances(_tokenOut, amountOut);
        emit ConvertRUSD(_recipient, _tokenOut, _amount, amountOut);
    }
}
