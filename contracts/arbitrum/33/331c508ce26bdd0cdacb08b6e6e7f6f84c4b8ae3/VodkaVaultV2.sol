// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IMasterChef.sol";
import "./ITokenBurnable.sol";
import "./IExchangeRouter.sol";
import "./Withdrawal.sol";
import "./EventUtils.sol";
import "./IWaterLendingHandler.sol";

import "./console.sol";

interface IVodkaV2GMXHandler {
    function getMarketTokenPrice(
        address longToken,
        bytes32 pnlFactorType,
        bool maximize
    ) external view returns (int256);

    function getEstimatedMarketTokenPrice(address _longToken) external view returns (int256);

    function tempPayableAddress() external view returns (address);

    function getLatestData(address _token, bool _inDecimal) external view returns (uint256);
}

interface IWater {
    function lend(uint256 _amount, address _receiver) external returns (bool);

    function repayDebt(uint256 leverage, uint256 debtValue) external;

    function getTotalDebt() external view returns (uint256);

    function updateTotalDebt(uint256 profit) external returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function balanceOfUSDC() external view returns (uint256);

    function asset() external view returns (address);
}

contract VodkaVaultV2 is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, ERC20BurnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;
    using MathUpgradeable for uint128;

    struct PositionInfo {
        uint256 deposit; // total amount of deposit
        uint256 position; // position size original + leverage
        uint256 price; // GMXMarket price
        uint256 closedPositionValue; // value of position when closed
        uint256 closePNL;
        address user; // user that created the position
        uint32 positionId;
        address liquidator; //address of the liquidator
        uint16 leverageMultiplier; // leverage multiplier, 2000 = 2x, 10000 = 10x
        bool closed;
        bool liquidated; // true if position was liquidated
        address longToken;
    }

    struct PositionDebt {
        uint256 longDebtValue;
        uint256 shortDebtValue;
    }

    struct FeeConfiguration {
        uint256 withdrawalFee;
        uint256 liquidatorsRewardPercentage;
        address feeReceiver;
        address waterFeeReceiver;
        uint256 fixedFeeSplit;
    }

    struct ExtraData {
        uint256 debtAndProfittoWater;
        uint256 toLeverageUser;
        uint256 waterProfit;
        uint256 leverageUserProfit;
        uint256 positionPreviousValue;
        address longToken;
        uint256 profits;
        uint256 returnedValue;
    }

    struct DepositRecord {
        address user;
        uint256 depositedAmount;
        uint256 receivedMarketTokens;
        uint256 feesPaid;
        bool success;
        uint16 leverageMultiplier;
        address longToken;
    }

    struct WithdrawRecord {
        address user;
        uint256 gmTokenWithdrawnAmount;
        uint256 returnedUSDC;
        uint256 feesPaid;
        uint256 profits;
        uint256 positionID;
        uint256 fullDebtValue;
        bool success;
        bool isLiquidation;
        address longToken;
        uint256 returnedLongAmount;
    }

    struct GMXAddresses {
        address depositHandler;
        address withdrawalHandler;
        address depositVault;
        address withdrawVault;
        address gmxRouter;
        address exchangeRouter;
    }

    struct GMXPoolAddresses {
        address longToken;
        address shortToken;
        address marketToken;
        address indexToken;
        address longTokenVault;
        address shortTokenVault;
    }

    struct StrategyAddresses {
        address USDC;
        address MasterChef;
        address WaterContract;
        address VodkaHandler;
        address WETH;
        address WaterLendingHandler;
    }

    struct DebtAdjustmentValues {
        uint256 debtAdjustment;
        uint256 time;
        uint256 debtValueRatio;
    }

    struct AmountBorrowed {
        uint256 shortTokenBorrowed; // USDC
        uint256 longTokenBorrowed; // ETH
    }

    FeeConfiguration public feeConfiguration;
    GMXAddresses public gmxAddresses;
    StrategyAddresses public strategyAddresses;
    DebtAdjustmentValues public debtAdjustmentValues;

    address[] public allUsers;

    uint256 public MCPID;
    uint256 public MAX_LEVERAGE;
    uint256 public MIN_LEVERAGE;
    uint256 public timeAdjustment;
    uint256 public gmxOpenCloseFees;
    address public feesSender;
    address public keeper;

    uint256 private DECIMAL;
    uint256 private MAX_BPS;
    uint256 public DTVLimit;

    mapping(address => PositionInfo[]) public positionInfo;
    mapping(address => PositionDebt[]) public positionDebt;
    mapping(bytes32 => DepositRecord) public depositRecord;
    mapping(address => bytes32[]) public userDepositKeyRecords;
    mapping(bytes32 => WithdrawRecord) public withdrawRecord;
    mapping(address => bytes32[]) public userWithdrawKeyRecords;
    mapping(address => bool) public allowedSenders;
    mapping(address => bool) public burner;
    mapping(address => bool) public isUser;
    mapping(address => bool) public isWhitelistedAsset;
    mapping(address => GMXPoolAddresses) public gmxPoolAddresses;
    mapping(address => mapping(uint256 => uint256)) public userDebtAdjustmentValue;
    mapping(address => mapping(uint256 => uint256)) public positionLeftoverDebt;
    mapping(address => mapping(uint256 => bool)) public inCloseProcess;
    mapping(bytes32 => AmountBorrowed) public amountBorrowed;

    uint256[50] private __gaps; 

    modifier InvalidID(uint256 positionId, address user) {
        require(positionId < positionInfo[user].length, "Vodka: positionID is not valid");
        _;
    }

    modifier zeroAddress(address addr) {
        require(addr != address(0), "Zero address");
        _;
    }

    modifier onlyBurner() {
        require(burner[msg.sender], "Not allowed to burn");
        _;
    }

    modifier onlyHandler() {
        require(msg.sender == strategyAddresses.VodkaHandler, "Not allowed to burn");
        _;
    }

    modifier onlyKeeper() {
        require(msg.sender == keeper, "Not allowed to burn");
        _;
    }

    /** --------------------- Event --------------------- */
    event GMXAddressesChanged(
        address newDepositHandler,
        address newWithdrawalHandler,
        address newDepositVault,
        address newWithdrawVault,
        address newgmxRouter,
        address newExchangeRouter
    );
    event Deposited(
        address indexed depositer,
        uint256 depositTokenAmount,
        uint256 createdAt,
        uint256 GMXMarketAmount,
        address longToken,
        uint256 _positionID
    );
    event ProtocolFeeChanged(
        address newFeeReceiver,
        uint256 newWithdrawalFee,
        address newWaterFeeReceiver,
        uint256 liquidatorsRewardPercentage
    );
    event Liquidation(
        address indexed liquidator,
        address indexed borrower,
        uint256 positionId,
        uint256 liquidatedAmount,
        uint256 outputAmount,
        uint256 time
    );

    event SetAllowedSenders(address indexed sender, bool allowed);
    event SetBurner(address indexed burner, bool allowed);
    event UpdateMaxAndMinLeverage(uint256 maxLeverage, uint256 minLeverage);
    event OpenRequest(address indexed user, uint256 amountAfterFee);
    event RequestFulfilled(address indexed user, uint256 openAmount, uint256 closedAmount);
    event SetAssetWhitelist(address indexed asset, address longToken, address shortToken, address marketToken, bool status);
    event FeeSplitSet(uint256 indexed split);
    event Liquidated(address indexed user, uint256 indexed positionId, address liquidator, uint256 amount, uint256 reward);
    event SetStrategyParams(address indexed MasterChef, uint256 MCPID, address water, address VodkaHandler);
    event WithdrawalFulfilled(
        address indexed user,
        uint256 amount,
        uint256 time,
        uint256 returnedUSDC,
        uint256 waterProfit,
        uint256 leverageUserProfit,
        address longToken,
        uint256 positionID,
        uint256 gmTokenWithdrawnAmount
    );
    event GMXOpenCloseFeeSet(uint256 indexed gmxOpenCloseFees);
    event DTVLimitSet(uint256 indexed DTVLimit);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _water) external initializer {
        // require(
        //     _usdc != address(0) &&
        //     _water != address(0) &&
        //     _depositHandler != address(0) &&
        //     _withdrawalHandler != address(0) &&
        //     _gmxToken != address(0) &&
        //     _depositVault != address(0) &&
        //     _gmxRouter != address(0) &&
        //     _exchangeRouter != address(0) &&
        //     _VodkaHandler != address(0),
        //     "Zero address"
        // );
        strategyAddresses.WaterContract = _water;
        debtAdjustmentValues.debtAdjustment = 1e18;
        debtAdjustmentValues.time = block.timestamp;

        MAX_LEVERAGE = 10_000;
        MIN_LEVERAGE = 2_000;
        DECIMAL = 1e18;
        MAX_BPS = 100_000;

        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init("VodkaV2", "V2POD");
    }

    /** ----------- Change onlyOwner functions ------------- */

    function takeAll(address _inputSsset) public onlyOwner {
        uint256 balance = IERC20Upgradeable(_inputSsset).balanceOf(address(this));
        IERC20Upgradeable(_inputSsset).transfer(msg.sender, balance);
    }

    function withdrawETH(address payable recipient) external onlyOwner {
        require(recipient != address(0), "Invalid address");
        (bool success, ) = recipient.call{ value: address(this).balance }("");
        require(success, "Transfer failed");
    }

    function setAllowed(address _sender, bool _allowed) public onlyOwner zeroAddress(_sender) {
        allowedSenders[_sender] = _allowed;
        emit SetAllowedSenders(_sender, _allowed);
    }

    function setGmxOpenCloseFees(uint256 _gmxOpenCloseFees) public onlyOwner {
        gmxOpenCloseFees = _gmxOpenCloseFees;
        emit GMXOpenCloseFeeSet(_gmxOpenCloseFees);
    }

    //@TODO ADD ONLY OWNER BACK
    function setDTVLimit(uint256 _DTVLimit) public {
        DTVLimit = _DTVLimit;
        emit DTVLimitSet(_DTVLimit);
    }

    function setAssetWhitelist(
        address _asset,
        address _longToken,
        address _shortToken,
        address _marketToken,
        address _indexToken,
        bool _status,
        address _longTokenVault,
        address _shortTokenVault
    ) public onlyOwner {
        GMXPoolAddresses storage gmp = gmxPoolAddresses[_asset];
        gmp.longToken = _longToken;
        gmp.shortToken = _shortToken;
        gmp.marketToken = _marketToken;
        gmp.indexToken = _indexToken;
        isWhitelistedAsset[_asset] = _status;
        gmp.longTokenVault = _longTokenVault;
        gmp.shortTokenVault = _shortTokenVault;

        emit SetAssetWhitelist(_asset, _longToken, _shortToken, _marketToken, _status);
    }

    function setBurner(address _burner, bool _allowed) public onlyOwner zeroAddress(_burner) {
        burner[_burner] = _allowed;
        emit SetBurner(_burner, _allowed);
    }

    function setStrategyParams(address _MasterChef, uint256 _MCPID, address _water, address _VodkaHandler, address _usdc,address _lendingHandler) public onlyOwner {
        strategyAddresses.MasterChef = _MasterChef;
        strategyAddresses.WaterContract = _water;
        strategyAddresses.VodkaHandler = _VodkaHandler;
        strategyAddresses.USDC = _usdc;
        strategyAddresses.WaterLendingHandler = _lendingHandler;
        MCPID = _MCPID;
        emit SetStrategyParams(_MasterChef, _MCPID, _water, _VodkaHandler);
    }

    function setMaxAndMinLeverage(uint256 _maxLeverage, uint256 _minLeverage) public onlyOwner {
        require(_maxLeverage >= _minLeverage, "Max leverage must be greater than min leverage");
        MAX_LEVERAGE = _maxLeverage;
        MIN_LEVERAGE = _minLeverage;
        emit UpdateMaxAndMinLeverage(_maxLeverage, _minLeverage);
    }

    function setProtocolFee(
        address _feeReceiver,
        uint256 _withdrawalFee,
        address _waterFeeReceiver,
        uint256 _liquidatorsRewardPercentage,
        uint256 _fixedFeeSplit
    ) external onlyOwner zeroAddress(_feeReceiver) zeroAddress(_waterFeeReceiver) {
        feeConfiguration.feeReceiver = _feeReceiver;
        feeConfiguration.withdrawalFee = _withdrawalFee;
        feeConfiguration.waterFeeReceiver = _waterFeeReceiver;
        feeConfiguration.liquidatorsRewardPercentage = _liquidatorsRewardPercentage;
        feeConfiguration.fixedFeeSplit = _fixedFeeSplit;

        emit ProtocolFeeChanged(_feeReceiver, _withdrawalFee, _waterFeeReceiver, _liquidatorsRewardPercentage);
    }

    function setGmxContracts(
        address _depositHandler,
        address _withdrawalHandler,
        address _depositVault,
        address _gmxRouter,
        address _exchangeRouter,
        address _withdrawVault
    ) external onlyOwner {
        gmxAddresses.depositHandler = _depositHandler;
        gmxAddresses.withdrawalHandler = _withdrawalHandler;
        gmxAddresses.depositVault = _depositVault;
        gmxAddresses.gmxRouter = _gmxRouter;
        gmxAddresses.exchangeRouter = _exchangeRouter;
        gmxAddresses.withdrawVault = _withdrawVault;

        emit GMXAddressesChanged(_depositHandler, _withdrawalHandler, _depositVault, _withdrawVault, _gmxRouter, _exchangeRouter);
    }

    function setDebtValueRatio(uint256 _debtValueRatio, uint256 _timeAdjustment) external onlyOwner {
        debtAdjustmentValues.debtValueRatio = _debtValueRatio;
        timeAdjustment = _timeAdjustment;
    }

    //@TODO ADD ONLY KEEPER BACK
    function updateDebtAdjustment() external {
        //will be re-enabled later on
        //require(getUtilizationRate() > (95 * 1e17) / 10, "Utilization rate is not greater than 95%");
        // ensure time difference when last update was made is greater than 72 hours
        //require(block.timestamp - debtAdjustmentValues.time > timeAdjustment, "Time difference is not greater than 72 hours");

        debtAdjustmentValues.debtAdjustment =
            debtAdjustmentValues.debtAdjustment +
            (debtAdjustmentValues.debtAdjustment * debtAdjustmentValues.debtValueRatio) /
            1e18;
        debtAdjustmentValues.time = block.timestamp;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /** ----------- View functions ------------- */

    function getGMPriceDuringExecution(address longToken, bytes32 pnlFactorType, bool maximize) internal view returns (uint256) {
        int256 gmPrice = IVodkaV2GMXHandler(strategyAddresses.VodkaHandler).getMarketTokenPrice(longToken, pnlFactorType, maximize);
        return uint256(gmPrice);
    }

    function getEstimatedGMPrice(address _longToken) public view returns (uint256) {
        int256 gmPrice = IVodkaV2GMXHandler(strategyAddresses.VodkaHandler).getEstimatedMarketTokenPrice(_longToken);
        return uint256(gmPrice);
    }

    function getAllUsers() public view returns (address[] memory) {
        return allUsers;
    }

    function getTotalOpenPosition(address _user) public view returns (uint256) {
        return positionInfo[_user].length;
    }

    function getUtilizationRate() public pure returns (uint256) {
        // @todo only the eth-usdc vault can decide how much is owned
        // uint256 totalWaterDebt = IWater(strategyAddresses.WaterContract).totalDebt();
        // uint256 totalWaterAssets = IWater(strategyAddresses.WaterContract).balanceOfUSDC();
        return 0; //totalWaterDebt == 0 ? 0 : totalWaterDebt.mulDiv(DECIMAL, totalWaterAssets + totalWaterDebt);
    }

    //@todo chainlink implemented;
    function getUpdatedDebt(uint256 _positionID, address _user) public view returns (uint256, uint256, uint256) {
        PositionInfo memory _positionInfo = positionInfo[_user][_positionID];
        PositionDebt memory pb = positionDebt[_user][_positionID];
        if (_positionInfo.closed || _positionInfo.liquidated) return (0, 0, 0);

        (uint256 currentPosition, ) = getEstimatedCurrentPosition(_positionID, _positionInfo.position, _user);
        uint256 longTokenOwed = pb.longDebtValue * IVodkaV2GMXHandler(strategyAddresses.VodkaHandler).getLatestData(_positionInfo.longToken,true) / 1e18;
        uint256 owedToWater = longTokenOwed + pb.shortDebtValue;
        uint256 currentDTV = owedToWater.mulDiv(DECIMAL, currentPosition);

        return (currentDTV, owedToWater, currentPosition);
    }

    function getEstimatedCurrentPosition(
        uint256 _positionID,
        uint256 _shares,
        address _user
    ) public view returns (uint256 currentValueInUSDC, uint256 previousValueInUSDC) {
        PositionInfo memory _positionInfo = positionInfo[_user][_positionID];

        uint256 userShares = (_shares == 0) ? _positionInfo.position : _shares;

        return (
            _convertGMXMarketToUSDC(userShares, getEstimatedGMPrice(_positionInfo.longToken)),
            _convertGMXMarketToUSDC(userShares, _positionInfo.price)
        );
    }

    // // for frontend only
    // function getCurrentLeverageAmount(uint256 _positionID, address _user) public view returns (uint256,uint256) {
    //     PositionInfo memory _positionInfo = positionInfo[_user][_positionID];
    //     uint256 previousDA = userDebtAdjustmentValue[_user][_positionID];
    //     uint256 userLeverageAmount = _positionInfo.leverageAmount;

    //     uint256 extraDebt;
    //     if (debtAdjustmentValues.debtAdjustment > previousDA) {
    //         userLeverageAmount = userLeverageAmount.mulDiv(debtAdjustmentValues.debtAdjustment, previousDA);
    //         extraDebt = userLeverageAmount - _positionInfo.leverageAmount;
    //     } else {
    //         extraDebt = positionLeftoverDebt[_user][_positionID];
    //     }
    //     return (userLeverageAmount,extraDebt);
    // }

    /** ----------- User functions ------------- */

    function requestOpenPosition(uint256 _amount, uint16 _leverage, address _longAsset) external payable whenNotPaused {
        require(_leverage >= MIN_LEVERAGE && _leverage <= MAX_LEVERAGE, "VodkaV2: Invalid leverage");
        require(_amount > 0, "VodkaV2: amount must be greater than zero");
        require(isWhitelistedAsset[_longAsset], "VodkaV2: asset is not whitelisted");

        IERC20Upgradeable(strategyAddresses.USDC).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 amount = _amount;
        
        GMXPoolAddresses memory gmp = gmxPoolAddresses[_longAsset];

        // @todo take leverage from vault
        console.log("before borrow",strategyAddresses.WaterLendingHandler);
        (uint256 longTokenAmount, uint256 shortTokenAmount) = IWaterLendingHandler(strategyAddresses.WaterLendingHandler).borrow(amount, _leverage, gmp.longToken, gmp.shortToken);
        console.log("longTokenAmount", longTokenAmount);
        console.log("shortTokenAmount", shortTokenAmount);

        IERC20Upgradeable(gmp.longToken).safeIncreaseAllowance(gmxAddresses.gmxRouter, longTokenAmount);
        IERC20Upgradeable(gmp.shortToken).safeIncreaseAllowance(gmxAddresses.gmxRouter, shortTokenAmount);
        IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(gmp.longToken, gmxAddresses.depositVault, longTokenAmount);
        IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(gmp.shortToken, gmxAddresses.depositVault, shortTokenAmount);

        IExchangeRouter(gmxAddresses.exchangeRouter).sendWnt{ value: msg.value }(gmxAddresses.depositVault, msg.value);

        IExchangeRouter.CreateDepositParams memory params = IExchangeRouter.CreateDepositParams({
            receiver: address(this),
            callbackContract: strategyAddresses.VodkaHandler,
            uiFeeReceiver: msg.sender,
            market: gmp.marketToken,
            initialLongToken: gmp.longToken,
            initialShortToken: gmp.shortToken,
            longTokenSwapPath: new address[](0),
            shortTokenSwapPath: new address[](0),
            minMarketTokens: 0,
            shouldUnwrapNativeToken: false,
            executionFee: gmxOpenCloseFees,
            callbackGasLimit: 2000000
        });

        bytes32 key = IExchangeRouter(gmxAddresses.exchangeRouter).createDeposit(params);

        DepositRecord storage dr = depositRecord[key];
        AmountBorrowed storage ab = amountBorrowed[key];

        ab.shortTokenBorrowed = shortTokenAmount;
        ab.longTokenBorrowed = longTokenAmount;

        dr.depositedAmount = amount;
        dr.feesPaid = msg.value;
        dr.user = msg.sender;
        dr.leverageMultiplier = _leverage;
        dr.longToken = gmp.longToken;
        userDepositKeyRecords[msg.sender].push(key);
    }

    function fulfillOpenPosition(bytes32 key, uint256 _receivedTokens) public onlyHandler returns (bool) {
        DepositRecord storage dr = depositRecord[key];
        AmountBorrowed storage ab = amountBorrowed[key];

        dr.receivedMarketTokens = _receivedTokens;
        address user = dr.user;

        PositionInfo memory _positionInfo = PositionInfo({
            user: dr.user,
            deposit: dr.depositedAmount,
            leverageMultiplier: dr.leverageMultiplier,
            position: dr.receivedMarketTokens,
            price: getGMPriceDuringExecution(dr.longToken, keccak256("MAX_PNL_FACTOR_FOR_DEPOSITS"), true),
            liquidated: false,
            closedPositionValue: 0,
            liquidator: address(0),
            closePNL: 0,
            positionId: uint32(positionInfo[user].length),
            closed: false,
            longToken: dr.longToken
        });

        PositionDebt memory pb = PositionDebt({
            longDebtValue: ab.longTokenBorrowed,
            shortDebtValue: ab.shortTokenBorrowed
        });

        positionDebt[user].push(pb);

        //frontend helper to fetch all users and then their userInfo
        if (isUser[user] == false) {
            isUser[user] = true;
            allUsers.push(user);
        }

        userDebtAdjustmentValue[dr.user][positionInfo[user].length] = debtAdjustmentValues.debtAdjustment;

        positionInfo[user].push(_positionInfo);
        // mint gmx shares to user
        _mint(user, dr.receivedMarketTokens);

        dr.success = true;

        emit Deposited(user, _positionInfo.deposit, block.timestamp, dr.receivedMarketTokens, dr.longToken, positionInfo[user].length);

        return true;
    }

    function requestClosePosition(uint256 _positionID, address _user) external payable InvalidID(_positionID, _user) nonReentrant {
        PositionInfo storage _positionInfo = positionInfo[_user][_positionID];
        require(!_positionInfo.liquidated || !_positionInfo.closed, "VodkaV2: position is closed or liquidated");
        require(_positionInfo.position > 0, "VodkaV2: position is not enough to close");
        require(msg.sender == _positionInfo.user, "VodkaV2: not allowed to close position");
        require(!inCloseProcess[_user][_positionID], "VodkaV2: close position request already ongoing");

        GMXPoolAddresses memory gmp = gmxPoolAddresses[_positionInfo.longToken];
        //uint256 extraDebt;
        //(_positionInfo.leverageAmount, extraDebt) = _actualizeExtraDebt(_positionID, _user);

        (uint256 currentDTV, , ) = getUpdatedDebt(_positionID, _user);
        if (currentDTV >= DTVLimit) {
            revert("Wait for liquidation");
        }

        _burn(_positionInfo.user, _positionInfo.position);
        IERC20Upgradeable(gmp.marketToken).approve(gmxAddresses.gmxRouter, _positionInfo.position);
        IExchangeRouter(gmxAddresses.exchangeRouter).sendWnt{ value: msg.value }(gmxAddresses.withdrawVault, msg.value);
        IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(gmp.marketToken, gmxAddresses.withdrawVault, _positionInfo.position);

        IExchangeRouter.CreateWithdrawalParams memory params = IExchangeRouter.CreateWithdrawalParams({
            receiver: strategyAddresses.VodkaHandler,
            callbackContract: strategyAddresses.VodkaHandler,
            uiFeeReceiver: _user,
            market: gmp.marketToken,
            longTokenSwapPath: new address[](0),
            shortTokenSwapPath: new address[](0),
            minLongTokenAmount: 0,
            minShortTokenAmount: 0,
            shouldUnwrapNativeToken: false,
            executionFee: gmxOpenCloseFees,
            callbackGasLimit: 2000000
        });

        bytes32 key = IExchangeRouter(gmxAddresses.exchangeRouter).createWithdrawal(params);

        WithdrawRecord storage wr = withdrawRecord[key];
        wr.gmTokenWithdrawnAmount = _positionInfo.position;
        wr.user = _user;
        wr.positionID = _positionID;
        wr.longToken = _positionInfo.longToken;
        userWithdrawKeyRecords[_user].push(key);
        inCloseProcess[_user][_positionID] = true;
    }

    function fulfillClosePosition(
        bytes32 _key,
        uint256 _returnedLongAmount,
        uint256 _returnedUSDC,
        uint256 _longAmountValue) public onlyHandler returns (bool) {
        WithdrawRecord storage wr = withdrawRecord[_key];
        PositionInfo storage _positionInfo = positionInfo[wr.user][wr.positionID];
        ExtraData memory extraData;
        PositionDebt memory pb = positionDebt[wr.user][wr.positionID];
        GMXPoolAddresses memory gmp = gmxPoolAddresses[wr.longToken];
        require(inCloseProcess[wr.user][wr.positionID], "VodkaV2: close position request not ongoing");

        uint256 positionID = wr.positionID;
        uint256 gmMarketAmount = wr.gmTokenWithdrawnAmount;

        wr.fullDebtValue = pb.longDebtValue + pb.shortDebtValue;
        wr.returnedUSDC = _returnedUSDC;
        wr.returnedLongAmount = _returnedLongAmount;
        extraData.longToken = wr.longToken;
        extraData.returnedValue = _longAmountValue + _returnedUSDC;

        extraData.positionPreviousValue = wr.fullDebtValue + _positionInfo.deposit;

        // // if (_returnedUSDC > extraData.positionPreviousValue) {
        // //     extraData.profits = _returnedUSDC - extraData.positionPreviousValue;
        // //     if (_returnedUSDC > pb.shortDebtValue) {
        // //         usdcProfits = _returnedUSDC - pb.longDebtValue;
        // //     }
        // //     if (_returnedLongAmount > pb.longDebtValue) {
        // //         longProfits = _returnedLongAmount - pb.longDebtValue;
        // //     }
        // // }

        uint256 waterRepayment;
        uint256 leverageUserProfits;
        uint256 waterProfits;
        // (uint256 waterProfits, uint256 leverageUserProfits) = _getProfitSplit(extraData.profits, _positionInfo.leverageMultiplier);

        //USDC
        extraData.toLeverageUser = (_returnedUSDC - pb.shortDebtValue - extraData.profits) + leverageUserProfits;
        waterRepayment = _returnedUSDC - extraData.toLeverageUser - waterProfits;
        
        if (waterProfits > 0) {
            IERC20Upgradeable(gmp.shortToken).safeTransfer(feeConfiguration.waterFeeReceiver, waterProfits);
        }

        IERC20Upgradeable(gmp.shortToken).safeIncreaseAllowance(strategyAddresses.WaterContract, waterRepayment);
        IWater(gmp.shortTokenVault).repayDebt(pb.shortDebtValue, waterRepayment);

        uint256 userShortAmountAfterFee;
        if (feeConfiguration.withdrawalFee > 0) {
            uint256 fee = extraData.toLeverageUser.mulDiv(feeConfiguration.withdrawalFee, MAX_BPS);
            IERC20Upgradeable(gmp.shortToken).safeTransfer(feeConfiguration.feeReceiver, fee);
            userShortAmountAfterFee = extraData.toLeverageUser - fee;
        } else {
            userShortAmountAfterFee = extraData.toLeverageUser;
        }

        IERC20Upgradeable(gmp.shortToken).safeTransfer(wr.user, userShortAmountAfterFee);



        //ETH
        extraData.toLeverageUser = (wr.returnedLongAmount - pb.longDebtValue - extraData.profits) + leverageUserProfits;
        waterRepayment = wr.returnedLongAmount - extraData.toLeverageUser - waterProfits;

        IERC20Upgradeable(wr.longToken).safeIncreaseAllowance(strategyAddresses.WaterContract, waterRepayment);
        IWater(gmp.longTokenVault).repayDebt(pb.longDebtValue, waterRepayment);

        uint256 userLongAmountAfterFee;
        if (feeConfiguration.withdrawalFee > 0) {
            uint256 ethFee = extraData.toLeverageUser.mulDiv(feeConfiguration.withdrawalFee, MAX_BPS);
            IERC20Upgradeable(gmp.shortToken).safeTransfer(feeConfiguration.feeReceiver, ethFee);
            userLongAmountAfterFee = extraData.toLeverageUser - ethFee;
        } else {
            userLongAmountAfterFee = extraData.toLeverageUser;
        }

        IERC20Upgradeable(wr.longToken).safeTransfer(wr.user, userLongAmountAfterFee);

        // _positionInfo.closedPositionValue += wr.returnedUSDC;
        // _positionInfo.closePNL = _returnedUSDC;
        _positionInfo.closed = true;
        _positionInfo.position = 0;

        // emit WithdrawalFulfilled(
        //     _positionInfo.user,
        //     amountAfterFee,
        //     block.timestamp,
        //     wr.returnedUSDC,
        //     extraData.waterProfit,
        //     extraData.leverageUserProfit,
        //     extraData.longToken,
        //     positionID,
        //     gmMarketAmount
        // );
        return (true);
    }

    function requestLiquidatePosition(address _user, uint256 _positionID) external payable nonReentrant {
        PositionInfo storage _positionInfo = positionInfo[_user][_positionID];
        require(!_positionInfo.liquidated, "VodkaV2: Already liquidated");
        require(_positionInfo.user != address(0), "VodkaV2: liquidation request does not exist");
        (uint256 currentDTV, , ) = getUpdatedDebt(_positionID, _user);
        require(currentDTV >= DTVLimit, "Liquidation Threshold Has Not Reached");
        uint256 assetToBeLiquidated = _positionInfo.position;

        _handlePODToken(_user, assetToBeLiquidated);
        GMXPoolAddresses memory gmp = gmxPoolAddresses[_positionInfo.longToken];

        IERC20Upgradeable(gmp.marketToken).approve(gmxAddresses.gmxRouter, assetToBeLiquidated);
        IExchangeRouter(gmxAddresses.exchangeRouter).sendWnt{ value: msg.value }(gmxAddresses.withdrawVault, msg.value);
        IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(gmp.marketToken, gmxAddresses.withdrawVault, assetToBeLiquidated);

        IExchangeRouter.CreateWithdrawalParams memory params = IExchangeRouter.CreateWithdrawalParams({
            receiver: strategyAddresses.VodkaHandler,
            callbackContract: strategyAddresses.VodkaHandler,
            uiFeeReceiver: msg.sender,
            market: gmp.marketToken,
            longTokenSwapPath: new address[](0),
            shortTokenSwapPath: new address[](0),
            minLongTokenAmount: 0,
            minShortTokenAmount: 0,
            shouldUnwrapNativeToken: false,
            executionFee: gmxOpenCloseFees,
            callbackGasLimit: 2000000
        });

        bytes32 key = IExchangeRouter(gmxAddresses.exchangeRouter).createWithdrawal(params);

        WithdrawRecord storage wr = withdrawRecord[key];
        wr.gmTokenWithdrawnAmount = assetToBeLiquidated;
        wr.user = _user;
        wr.positionID = _positionID;
        wr.isLiquidation = true;

        userWithdrawKeyRecords[_user].push(key);
    }

    function fulfillLiquidation(bytes32 _key, uint256 _returnedLongAmount, uint256 _returnedUSDC) external returns (bool) {
        WithdrawRecord storage wr = withdrawRecord[_key];
        PositionInfo storage _positionInfo = positionInfo[wr.user][wr.positionID];
        wr.returnedUSDC = _returnedUSDC;

        uint256 liquidatorReward = wr.returnedUSDC.mulDiv(feeConfiguration.liquidatorsRewardPercentage, MAX_BPS);

        uint256 amountAfterLiquidatorReward = wr.returnedUSDC - liquidatorReward;
        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.WaterContract, amountAfterLiquidatorReward);

        // @todo payment should be made via the eth-usdc vault
        // IWater(strategyAddresses.WaterContract).repayDebt(debtPortion, amountAfterLiquidatorReward);

        IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(msg.sender, liquidatorReward);

        _positionInfo.liquidated = true;
        _positionInfo.closed = true;
        _positionInfo.position = 0;
        //_positionInfo.leverageAmount = 0;

        emit Liquidation(msg.sender, wr.user, wr.positionID, wr.gmTokenWithdrawnAmount, wr.returnedUSDC, block.timestamp);
        return (true);
    }

    /** ----------- Token functions ------------- */

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        require(allowedSenders[from] || allowedSenders[to] || allowedSenders[spender], "ERC20: transfer not allowed");
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address ownerOf = _msgSender();
        require(allowedSenders[ownerOf] || allowedSenders[to], "ERC20: transfer not allowed");
        _transfer(ownerOf, to, amount);
        return true;
    }

    function burn(uint256 amount) public virtual override onlyBurner {
        _burn(_msgSender(), amount);
    }

    /** ----------- Internal functions ------------- */

    function _actualizeExtraDebt(uint256 _positionID, address _user) internal returns (uint256, uint256) {
        PositionInfo memory _positionInfo = positionInfo[_user][_positionID];
        uint256 previousDA = userDebtAdjustmentValue[_user][_positionID];
        uint256 userLeverageAmount = 0;

        if (debtAdjustmentValues.debtAdjustment > previousDA) {
            userLeverageAmount = userLeverageAmount.mulDiv(debtAdjustmentValues.debtAdjustment, previousDA);
            uint256 extraDebt = userLeverageAmount - 0;
            positionLeftoverDebt[_user][_positionID] += extraDebt;
            userDebtAdjustmentValue[_user][_positionID] = debtAdjustmentValues.debtAdjustment;
        }
        return (userLeverageAmount, positionLeftoverDebt[_user][_positionID]);
    }

    function _getProfitSplit(uint256 _profit, uint256 _leverage) internal view returns (uint256, uint256) {
        if (_profit == 0) {
            return (0, 0);
        }
        uint256 split = (feeConfiguration.fixedFeeSplit * _leverage + (feeConfiguration.fixedFeeSplit * 10000)) / 100;
        uint256 toWater = (_profit * split) / 10000;
        uint256 toVodkaV2User = _profit - toWater;

        return (toWater, toVodkaV2User);
    }

    function _convertGMXMarketToUSDC(uint256 _amount, uint256 _GMXMarketPrice) internal pure returns (uint256) {
        return _amount.mulDiv(_GMXMarketPrice, (10 ** 18)) / 1e12;
    }

    function _handlePODToken(address _user, uint256 position) internal {
        uint256 userAmountStaked;
        if (strategyAddresses.MasterChef != address(0)) {
            (userAmountStaked, ) = IMasterChef(strategyAddresses.MasterChef).userInfo(MCPID, _user);
            if (userAmountStaked > 0) {
                uint256 amountToBurnFromUser;
                if (userAmountStaked > position) {
                    amountToBurnFromUser = position;
                } else {
                    amountToBurnFromUser = userAmountStaked;
                    uint256 _position = position - userAmountStaked;
                    _burn(_user, _position);
                }
                IMasterChef(strategyAddresses.MasterChef).unstakeAndLiquidate(MCPID, _user, amountToBurnFromUser);
            }
            if (userAmountStaked == 0) {
                _burn(_user, position);
            }
        }
    }

    receive() external payable {
        require(msg.sender == gmxAddresses.depositVault || msg.sender == gmxAddresses.withdrawVault, "Not temp payable address");
        feesSender = msg.sender;
        payable(IVodkaV2GMXHandler(strategyAddresses.VodkaHandler).tempPayableAddress()).transfer(address(this).balance);
    }
}

