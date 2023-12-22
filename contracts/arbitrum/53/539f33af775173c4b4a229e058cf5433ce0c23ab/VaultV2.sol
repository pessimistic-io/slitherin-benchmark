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

contract VaultV2 is IVaultV2, Constants, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using EnumerableMapUpgradeable for EnumerableMapUpgradeable.AddressToUintMap;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    EnumerableSetUpgradeable.AddressSet private collateralTokens;
    EnumerableSetUpgradeable.AddressSet private tradingTokens;
    mapping(address => uint256) private tokenBalances;

    uint256 public aumAddition;
    uint256 public aumDeduction;
    address public ROLP;
    address public rUSD;

    IPriceManager public priceManager;
    ISettingsManagerV2 public settingsManager;
    IPositionKeeperV2 public positionKeeper;
    address public positionHandler;
    IReferralSystemV2 public referralSystem;
    address public swapRouter;
    address public positionRouter;
    address public converter; //Deprecated, not use
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
        address rUSD, 
        address priceManager, 
        address settingsManager,
        address positionRouter,
        address positionHandler,
        address positionKeeper,
        address vaultUtils
    );
    event SetSwapRouter(address swapRouter);
    event RescueERC20(address indexed recipient, address indexed token, uint256 amount);
    event SetRefferalSystem(address referralSystem);

    function initialize(
        address _ROLP, 
        address _RUSD
    ) public reinitializer(10) {
        require(AddressUpgradeable.isContract(_ROLP) 
            && AddressUpgradeable.isContract(_RUSD), "IVLCA");
        __Ownable_init();
        ROLP = _ROLP;
        rUSD = _RUSD;
        converter = address(0);
        swapRouter = address(0);
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
            rUSD, 
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
        referralSystem = IReferralSystemV2(_refferalSystem);
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

        if (_token == rUSD) {
            IBurnable(rUSD).burn(_account, _amount);
        } else {
            _transferFrom(_token, _account, _amount);
        }

        uint256 amountInUSD = _token == rUSD ? _amount: priceManager.fromTokenToUSD(_token, _amount);
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
        bool isPositionHandler = msg.sender == positionHandler;
        require(isPositionHandler, "Forbidden");
        address referrer;
        uint256 discountFee;
        uint256 rebatePercentage;
        uint256 esRebatePercentage;
        
        //Apply discount from positionHandler only, re-check isPositionHandler for reservion of other cases
        if (isPositionHandler && _fee > 0 && address(referralSystem) != address(0)) {
            uint256 discountsharePercentage;
            (referrer, discountsharePercentage, rebatePercentage, esRebatePercentage) = referralSystem.getDiscountableInternal(_account, _fee);

            //Apply discount fee first
            if (discountsharePercentage > 0) {
                discountFee = _fee * discountsharePercentage / BASIS_POINTS_DIVISOR;

                if (discountFee >= _fee) {
                    discountFee = _fee;
                }

                _fee -= discountFee;
            }
        }

        uint256 tokenAmountOut = _takeAssetOut(
            _account, 
            _fee,
            rebatePercentage + esRebatePercentage,
            _usdOut, 
            _token, 
            _tokenPrice
        );

        emit TakeAssetOut(
            _key, 
            _account, 
            referrer, 
            _usdOut, 
            _fee, 
            _token, 
            tokenAmountOut, 
            _tokenPrice
        );
    }

    function _takeAssetOut(
        address _account, 
        uint256 _fee, 
        uint256 _rebatePercentage,
        uint256 _usdOut, 
        address _token, 
        uint256 _tokenPrice
    ) internal returns (uint256) {
        require(_token != address(0) && _tokenPrice > 0, "Invalid asset");
        uint256 usdOutAfterFee = _usdOut == 0 ? 0 : _usdOut - _fee;
        //Force convert 1-1 if stable
        uint256 tokenPrice = settingsManager.isStable(_token) ? PRICE_PRECISION : _tokenPrice;
        uint256 tokenAmountOut = usdOutAfterFee == 0 ? 0 : priceManager.fromUSDToToken(_token, usdOutAfterFee, tokenPrice);
        _transferTo(_token, tokenAmountOut, _account);
        _decreaseTokenBalances(_token, tokenAmountOut);
        _collectFee(
            _fee,
            _rebatePercentage,
            settingsManager.getFeeManager(),
            true
        );

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
        _isPositionHandler(msg.sender, true);

        if (_account != address(0) && _amount > 0) {
            IMintable(rUSD).mint(_account, _amount);
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
                uint256 vaultAvailable = IERC20Upgradeable(_token).balanceOf(address(this));
                require(vaultAvailable >= _amount && vaultAvailable - _amount 
                    >= minimumVaultReserve, "VREXD"); //VaultReserve exceeded
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
        return (aumDeduction > aum ? 0 : aum - aumDeduction) + tokenBalances[rUSD];
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

        _collectFeeNonRebate(usdAmountFee, settingsManager.getFeeManager(), false);
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
            : (_tokenOut == rUSD ? usdAmountAfterFee: priceManager.fromUSDToToken(_tokenOut, usdAmountAfterFee));
        require(amountOutInToken > 0, "Unstaking amount too low");

        _decreaseTokenBalances(_tokenOut, amountOutInToken);
        _decreasePoolAmount(_tokenOut, usdAmountAfterFee);
        _collectFeeNonRebate(usdAmountFee, settingsManager.getFeeManager(), false);
        require(IERC20Upgradeable(_tokenOut).balanceOf(address(this)) >= amountOutInToken, "Insufficient");
        _transferTo(_tokenOut, amountOutInToken, _receiver);
        stakeAmounts[_tokenOut] -= usdAmountAfterFee;
        emit Unstake(msg.sender, _tokenOut, _rolpAmount, amountOutInToken);
    }

    function totalROLP() public view returns (uint256) {
        return IERC20Upgradeable(ROLP).totalSupply();
    }

    function totalRUSD() public view returns (uint256) {
        return IERC20Upgradeable(rUSD).totalSupply();
    }

    function distributeFee(bytes32 _key, address _account, uint256 _fee) external override {
        _isPositionHandler(msg.sender, true);
        address feeManager = settingsManager.feeManager();
        _collectFeeNonRebate(_fee, feeManager, true);

        if (_fee > 0) {
            emit DistributeFee(_key, _account, feeManager, _fee);
        }
    }


    function _collectFeeNonRebate(
        uint256 _fee,
        address _feeManager,
        bool _isReserve
    ) internal {
        _collectFee(
            _fee,
            0,
            _feeManager,
            _isReserve
        );
    }

    function _collectFee(
        uint256 _fee,
        uint256 _rebatePercentage,
        address _feeManager,
        bool _isReserve
    ) internal {
        uint256 rebateAmount = _rebatePercentage == 0 ? 0 : _fee * _rebatePercentage / BASIS_POINTS_DIVISOR;
        uint256 feeAfterRebate = rebateAmount >= _fee ? 0 : _fee - rebateAmount;

        if (feeAfterRebate > 0) {
            //Stake/Unstake will take full fee, otherwise reserve to vault
            uint256 feeReserve = _isReserve ? (feeAfterRebate * settingsManager.feeRewardBasisPoints() / BASIS_POINTS_DIVISOR) : 0;
            uint256 systemFee = feeReserve >= feeAfterRebate ? 0 : feeAfterRebate - feeReserve;
            feeAfterRebate = systemFee >= feeAfterRebate ? 0 : feeAfterRebate - systemFee;

            if (systemFee > 0) {
                require(_feeManager != address(0), "IVLFM"); //Invalid feeManager
                IMintable(rUSD).mint(_feeManager, systemFee);
            }
        }

        if (feeAfterRebate > 0) {
            //Reserve fee for vault
            IMintable(rUSD).mint(address(this), feeAfterRebate);
            _increaseTokenBalances(rUSD, feeAfterRebate);
        }
    }

    function rescueERC20(address _recipient, address _token, uint256 _amount) external onlyOwner {
        bool isVaultBalance = tokenBalances[_token] > 0 && _token != rUSD;
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


    /*
    @dev: Let updater hotfix system amount
    */
    function updateSystemAmount(uint256 _type, uint256 _amount, address _token, bool _isPlus) external onlyOwner {
        if (_type == 0) {
            if (_isPlus) {
                _increasePoolAmount(_token, _amount);
            } else {
                _decreasePoolAmount(_token, _amount);
            }
        } else if (_type == 1) {
            _updateGuaranteedAmount(_token, _amount, _isPlus);
        } else if (_type == 2) {
            _updateReservedAmount(_token, _amount, _isPlus);
        } else {
            revert("InvalidType");
        }
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
}
