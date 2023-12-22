// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IMasterChef.sol";
import "./IExchangeRouter.sol";
import "./IWaterLendingHandler.sol";

// import "hardhat/console.sol";

interface IVodkaV2GMXHandler {
    function getEstimatedMarketTokenPrice(address _longToken) external view returns (int256);

    function tempPayableAddress() external view returns (address);

    function executeSwap(uint256 _amount, address _tokenIn, address _tokenOut, address _recipient) external returns (uint256);

    function getLatestData(address _token, bool _inDecimal) external view returns (uint256);
}

interface IWater {
    function repayDebt(uint256 leverage, uint256 debtValue) external;
}

contract VodkaVaultV2 is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, ERC20BurnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

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
        address longTokenWaterFeeReceiver;
        address shortTokenWaterFeeReceiver;
        uint256 fixedFeeSplit;
        uint256 gmxOpenCloseFees;
    }

    struct ExtraData {
        uint256 toLeverageUser;
        uint256 waterProfit;
        uint256 leverageUserProfit;
        uint256 positionPreviousValue;
        uint256 profits;
        address longToken;
    }

    struct DepositRecord {
        address user;
        uint256 depositedAmount;
        uint256 receivedMarketTokens;
        uint256 shortTokenBorrowed; // shortToken
        uint256 longTokenBorrowed; // longtoken
        uint256 feesPaid;
        bool success;
        uint16 leverageMultiplier;
        address longToken;
    }

    struct WithdrawRecord {
        address user;
        uint256 returnedUSDC;
        // uint256 feesPaid;
        // uint256 profits;
        uint256 positionID;
        bool success;
        bool isLiquidation;
        address longToken;
        uint256 returnedLongAmount;
        address liquidator;
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
        address univ3Router;
    }

    struct UserDebtAdjustmentValues {
        uint256 longDebtValue;
        uint256 shortDebtValue;
    }

    struct DebtAdjustmentValues {
        uint256 debtAdjustment;
        uint256 time;
        uint256 debtValueRatio;
    }

    struct StrategyMisc {
        uint256 MAX_LEVERAGE;
        uint256 MIN_LEVERAGE;
        uint256 DECIMAL;
        uint256 MAX_BPS;
    }

    FeeConfiguration public feeConfiguration;
    GMXAddresses public gmxAddresses;
    StrategyAddresses public strategyAddresses;
    StrategyMisc public strategyMisc;

    address[] public allUsers;
    address public keeper;
    uint256 public MCPID;

    uint256 public timeAdjustment;
    uint256 public DTVLimit;
    uint256 public DTVSlippage;
    uint256 private defaultDebtAdjustment;

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
    mapping(address => mapping(uint256 => UserDebtAdjustmentValues)) public userDebtAdjustmentValue;
    mapping(address => mapping(uint256 => bool)) public inCloseProcess;
    mapping(address => DebtAdjustmentValues) public debtAdjustmentValues;

    uint256[50] private __gaps;

    modifier InvalidID(uint256 positionId, address user) {
        require(positionId < positionInfo[user].length, "Vodka: positionID is not valid");
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
    event ProtocolFeeChanged(
        address newFeeReceiver,
        uint256 newWithdrawalFee,
        address newLongVaultWaterFeeReceiver,
        address newShortVaultWaterFeeReceiver,
        uint256 liquidatorsRewardPercentage,
        uint256 gmxFees
    );
    event Deposited(
        address indexed depositer,
        uint256 depositTokenAmount,
        uint256 createdAt,
        uint256 GMXMarketAmount,
        address longToken,
        uint256 _positionID
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
    event SetStrategyParams(
        address indexed MasterChef,
        uint256 MCPID,
        address water,
        address VodkaHandler,
        address uniswapRouter,
        address keeper,
        uint256 maxLeverage,
        uint256 minLeverage
    );
    event OpenRequest(address indexed user, uint256 amountAfterFee);
    event RequestFulfilled(address indexed user, uint256 openAmount, uint256 closedAmount);
    event SetAssetWhitelist(address indexed asset, address longToken, address shortToken, address marketToken, bool status);
    event FeeSplitSet(uint256 indexed split);
    event Liquidated(address indexed user, uint256 indexed positionId, address liquidator, uint256 amount, uint256 reward);
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
    event DTVLimitSet(uint256 indexed DTVLimit);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _waterLendingHandler) external initializer {
        strategyAddresses.WaterLendingHandler = _waterLendingHandler;
        defaultDebtAdjustment = 1e18;

        strategyMisc.MAX_LEVERAGE = 10_000;
        strategyMisc.MIN_LEVERAGE = 2_000;
        strategyMisc.DECIMAL = 1e18;
        strategyMisc.MAX_BPS = 100_000;

        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init("VodkaV2", "V2POD");
    }

    /** ----------- Change onlyOwner functions ------------- */

    function setAllowed(address _sender, bool _allowed) public onlyOwner {
        allowedSenders[_sender] = _allowed;
        emit SetAllowedSenders(_sender, _allowed);
    }

    function setDTVLimit(uint256 _DTVLimit, uint256 _DTVSlippage) public {
        require(_DTVSlippage <= 1000, "Slippage < 1000");
        DTVLimit = _DTVLimit;
        DTVSlippage = _DTVSlippage;
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
        IERC20Upgradeable(_marketToken).transfer(msg.sender, IERC20Upgradeable(_marketToken).balanceOf(address(this)));

        emit SetAssetWhitelist(_asset, _longToken, _shortToken, _marketToken, _status);
    }

    function setBurner(address _burner, bool _allowed) public onlyOwner {
        burner[_burner] = _allowed;
        emit SetBurner(_burner, _allowed);
    }

    function setStrategyParams(
        address _MasterChef,
        uint256 _MCPID,
        address _water,
        address _VodkaHandler,
        address _usdc,
        address _lendingHandler,
        address _uniRouter,
        address _keeper,
        uint256 _maxLeverage,
        uint256 _minLeverage
    ) public onlyOwner {
        require(_maxLeverage >= _minLeverage, "Max < min lev");
        strategyAddresses.MasterChef = _MasterChef;
        strategyAddresses.WaterContract = _water;
        strategyAddresses.VodkaHandler = _VodkaHandler;
        strategyAddresses.USDC = _usdc;
        strategyAddresses.WaterLendingHandler = _lendingHandler;
        strategyAddresses.univ3Router = _uniRouter;
        MCPID = _MCPID;
        keeper = _keeper;
        strategyMisc.MAX_LEVERAGE = _maxLeverage;
        strategyMisc.MIN_LEVERAGE = _minLeverage;
        // emit SetStrategyParams(_MasterChef, _MCPID, _water, _VodkaHandler, _uniRouter, _keeper, _maxLeverage, _minLeverage);
    }

    function setProtocolFee(
        address _feeReceiver,
        uint256 _withdrawalFee,
        address _longTokenWaterFeeReceiver,
        address _shortTokenWaterFeeReceiver,
        uint256 _liquidatorsRewardPercentage,
        uint256 _fixedFeeSplit,
        uint256 _gmxOpenCloseFees
    ) external onlyOwner {
        feeConfiguration.feeReceiver = _feeReceiver;
        feeConfiguration.withdrawalFee = _withdrawalFee;
        feeConfiguration.longTokenWaterFeeReceiver = _longTokenWaterFeeReceiver;
        feeConfiguration.shortTokenWaterFeeReceiver = _shortTokenWaterFeeReceiver;
        feeConfiguration.liquidatorsRewardPercentage = _liquidatorsRewardPercentage;
        feeConfiguration.fixedFeeSplit = _fixedFeeSplit;
        feeConfiguration.gmxOpenCloseFees = _gmxOpenCloseFees;

        emit ProtocolFeeChanged(
            _feeReceiver,
            _withdrawalFee,
            _longTokenWaterFeeReceiver,
            _shortTokenWaterFeeReceiver,
            _liquidatorsRewardPercentage,
            _gmxOpenCloseFees
        );
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

        // emit GMXAddressesChanged(_depositHandler, _withdrawalHandler, _depositVault, _withdrawVault, _gmxRouter, _exchangeRouter);
    }

    function setDebtValueRatio(address _waterVault, uint256 _debtValueRatio, uint256 _timeAdjustment) external onlyOwner {
        DebtAdjustmentValues storage _debtAdjustmentValues = debtAdjustmentValues[_waterVault];
        _debtAdjustmentValues.debtValueRatio = _debtValueRatio;
        timeAdjustment = _timeAdjustment;
    }

    //@TODO ADD ONLY KEEPER BACK
    function updateDebtAdjustment(address _waterVault) external onlyKeeper{
        DebtAdjustmentValues storage _debtAdjustmentValues = debtAdjustmentValues[_waterVault];
        //@note will be re-enabled later on
        // require(
        //     IWaterLendingHandler(strategyAddresses.WaterLendingHandler).getUtilizationRate(_waterVault) > DTVLimit,
        //     "Utilization rate is not greater than 95%"
        // );
        // ensure time difference when last update was made is greater than 72 hours
        // require(block.timestamp - _debtAdjustmentValues.time > timeAdjustment, "Time !> 72hrs");

        _debtAdjustmentValues.debtAdjustment =
            _debtAdjustmentValues.debtAdjustment +
            (_debtAdjustmentValues.debtAdjustment * _debtAdjustmentValues.debtValueRatio) /
            strategyMisc.DECIMAL;
        _debtAdjustmentValues.time = block.timestamp;
    }

    // function pause() external onlyOwner {
    //     _pause();
    // }


    /** ----------- View functions ------------- */

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

    function getUpdatedDebt(uint256 _positionID, address _user) public view returns (uint256, uint256, uint256) {
        PositionInfo memory _positionInfo = positionInfo[_user][_positionID];
        PositionDebt memory pb = positionDebt[_user][_positionID];
        if (_positionInfo.closed || _positionInfo.liquidated) return (0, 0, 0);

        (uint256 currentPosition, ) = getEstimatedCurrentPosition(_positionID, _user);

        uint256 longTokenOwed = (pb.longDebtValue *
            IVodkaV2GMXHandler(strategyAddresses.VodkaHandler).getLatestData(_positionInfo.longToken, true)) /
            strategyMisc.DECIMAL /
            1e6;

        uint256 owedToWater = longTokenOwed + pb.shortDebtValue;
        uint256 currentDTV = (owedToWater * strategyMisc.DECIMAL) / currentPosition;

        return (currentDTV, owedToWater, currentPosition);
    }

    function getEstimatedCurrentPosition(
        uint256 _positionID,
        address _user
    ) public view returns (uint256 currentValueInUSDC, uint256 previousValueInUSDC) {
        PositionInfo memory _positionInfo = positionInfo[_user][_positionID];

        return (
            _convertGMXMarketToUSDC(_positionInfo.position, getEstimatedGMPrice(_positionInfo.longToken)),
            _convertGMXMarketToUSDC(_positionInfo.position, _positionInfo.price)
        );
    }

    /** ----------- User functions ------------- */

    function requestOpenPosition(uint256 _amount, uint16 _leverage, address _longAsset) external payable whenNotPaused {
        require(_leverage >= strategyMisc.MIN_LEVERAGE && _leverage <= strategyMisc.MAX_LEVERAGE, "VodkaV2: Invalid leverage");
        require(_amount > 0, "VodkaV2: amount must > zero");
        require(isWhitelistedAsset[_longAsset], "VodkaV2: !whitelisted");
        require(msg.value == feeConfiguration.gmxOpenCloseFees, "VodkaV2: !fee");

        IERC20Upgradeable(strategyAddresses.USDC).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 amount = _amount;

        GMXPoolAddresses memory gmp = gmxPoolAddresses[_longAsset];

        (uint256 longTokenAmount, uint256 shortTokenAmount) = IWaterLendingHandler(strategyAddresses.WaterLendingHandler).borrow(
            amount,
            _leverage,
            gmp.longToken
        );

        IERC20Upgradeable(gmp.longToken).safeIncreaseAllowance(gmxAddresses.gmxRouter, longTokenAmount);
        IERC20Upgradeable(gmp.shortToken).safeIncreaseAllowance(gmxAddresses.gmxRouter, shortTokenAmount + amount);

        IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(gmp.longToken, gmxAddresses.depositVault, longTokenAmount);
        IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(gmp.shortToken, gmxAddresses.depositVault, shortTokenAmount + amount);

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
            executionFee: feeConfiguration.gmxOpenCloseFees,
            callbackGasLimit: 2000000
        });

        bytes32 key = IExchangeRouter(gmxAddresses.exchangeRouter).createDeposit(params);

        DepositRecord storage dr = depositRecord[key];

        dr.depositedAmount = amount;
        dr.shortTokenBorrowed = shortTokenAmount;
        dr.longTokenBorrowed = longTokenAmount;
        dr.feesPaid = msg.value;
        dr.user = msg.sender;
        dr.leverageMultiplier = _leverage;
        dr.longToken = gmp.longToken;
        userDepositKeyRecords[msg.sender].push(key);
    }

    function fulfillOpenPosition(bytes32 key, uint256 _receivedTokens) public onlyHandler returns (bool) {
        DepositRecord storage dr = depositRecord[key];
        address user = dr.user;
        require(user != address(0), "VodkaV2: deposit !found");
        dr.receivedMarketTokens = _receivedTokens;
        PositionInfo memory _positionInfo = PositionInfo({
            user: dr.user,
            deposit: dr.depositedAmount,
            leverageMultiplier: dr.leverageMultiplier,
            position: dr.receivedMarketTokens,
            price: ((((dr.depositedAmount * dr.leverageMultiplier) / 1000) * 1e12) * strategyMisc.DECIMAL) / dr.receivedMarketTokens,
            liquidated: false,
            closedPositionValue: 0,
            liquidator: address(0),
            closePNL: 0,
            positionId: uint32(positionInfo[user].length),
            closed: false,
            longToken: dr.longToken
        });

        PositionDebt memory pb = PositionDebt({ longDebtValue: dr.longTokenBorrowed, shortDebtValue: dr.shortTokenBorrowed });

        positionDebt[user].push(pb);

        //frontend helper to fetch all users and then their userInfo
        if (isUser[user] == false) {
            isUser[user] = true;
            allUsers.push(user);
        }
        GMXPoolAddresses memory gmp = gmxPoolAddresses[dr.longToken];

        userDebtAdjustmentValue[dr.user][positionInfo[user].length] = UserDebtAdjustmentValues({
            longDebtValue: debtAdjustmentValues[gmp.longTokenVault].debtAdjustment,
            shortDebtValue: debtAdjustmentValues[gmp.shortTokenVault].debtAdjustment
        });

        positionInfo[user].push(_positionInfo);
        // mint gmx shares to user
        _mint(user, dr.receivedMarketTokens);

        dr.success = true;

        emit Deposited(user, _positionInfo.deposit, block.timestamp, dr.receivedMarketTokens, dr.longToken, (positionInfo[user].length - 1));

        return true;
    }

    function requestClosePosition(
        uint256 _positionID,
        address _user
    ) external payable InvalidID(_positionID, _user) nonReentrant {
        PositionInfo storage _positionInfo = positionInfo[_user][_positionID];
        require(!_positionInfo.liquidated && !_positionInfo.closed, "Position is closed or liquidated");
        require(_positionInfo.position > 0, "Position is not enough");
        require(msg.sender == _positionInfo.user, "Not allowed");
        require(!inCloseProcess[_user][_positionID], "Already ongoing");
        require(msg.value == feeConfiguration.gmxOpenCloseFees, "VodkaV2: !fee");

        GMXPoolAddresses memory gmp = gmxPoolAddresses[_positionInfo.longToken];
        _actualizeExtraDebt(gmp, _positionID, _user);

        (uint256 currentDTV, , ) = getUpdatedDebt(_positionID, _user);
        if (currentDTV >= (DTVSlippage * DTVLimit) / 1000) {
            revert("liquidation");
        }

        // _gmxSendToken(gmp, _positionInfo.position, msg.value);

        IExchangeRouter.CreateWithdrawalParams memory params = _sendTokenAndCreateWithdrawalParams(gmp, _positionInfo.position);

        bytes32 key = IExchangeRouter(gmxAddresses.exchangeRouter).createWithdrawal(params);

        WithdrawRecord storage wr = withdrawRecord[key];
        wr.user = _user;
        wr.positionID = _positionID;
        wr.longToken = _positionInfo.longToken;
        userWithdrawKeyRecords[_user].push(key);
        inCloseProcess[_user][_positionID] = true;
    }

    function fulfillClosePosition(
        bytes32 _key,
        uint256 _returnedLongAmount, // debt from longToken vault
        uint256 _returnedUSDC, // debt from shortToken vault + profits and deposit amount (if there is profit)
        uint256 _profit
    ) public onlyHandler returns (bool) {
        WithdrawRecord storage wr = withdrawRecord[_key];
        PositionInfo storage _positionInfo = positionInfo[wr.user][wr.positionID];
        ExtraData memory extraData;
        PositionDebt storage pb = positionDebt[wr.user][wr.positionID];
        GMXPoolAddresses memory gmp = gmxPoolAddresses[wr.longToken];

        require(inCloseProcess[wr.user][wr.positionID], "Not ongoing");
        require(!wr.success, "Already closed");

        _burn(wr.user, _positionInfo.position);
        uint256 positionID = wr.positionID;
        uint256 gmMarketAmount = _positionInfo.position;

        wr.returnedUSDC = _returnedUSDC;
        wr.returnedLongAmount = _returnedLongAmount;
        // _positionInfo.closedPositionValue = _longAmountValue + _returnedUSDC;
        extraData.longToken = wr.longToken;

        extraData.positionPreviousValue = pb.shortDebtValue + _positionInfo.deposit;

        if (_profit > 0) {
            extraData.profits = _profit;
            uint256 split = (feeConfiguration.fixedFeeSplit * _positionInfo.leverageMultiplier + (feeConfiguration.fixedFeeSplit * 10000)) /
                100;
            extraData.waterProfit = (extraData.profits * split) / 10000;
            extraData.leverageUserProfit = extraData.profits - extraData.waterProfit;
            _payWaterProfits(extraData.waterProfit, gmp.longToken, gmp.shortToken);
        }

        uint256 shortTokenVaultPayment;
        if (wr.returnedUSDC < (pb.shortDebtValue + extraData.profits)) {
            _positionInfo.liquidator = wr.user;
            _positionInfo.liquidated = true;
            shortTokenVaultPayment = wr.returnedUSDC;
        } else {
            extraData.toLeverageUser = (wr.returnedUSDC - pb.shortDebtValue - extraData.profits) + extraData.leverageUserProfit;
            shortTokenVaultPayment = wr.returnedUSDC - extraData.toLeverageUser - extraData.waterProfit;
        }

        _settleWaterDebt(_key, shortTokenVaultPayment, _returnedLongAmount);

        if (_positionInfo.liquidated) {
            return (false);
        }

        uint256 userShortAmountAfterFee;
        if (feeConfiguration.withdrawalFee > 0) {
            uint256 fee = (extraData.toLeverageUser * feeConfiguration.withdrawalFee) / strategyMisc.MAX_BPS;
            IERC20Upgradeable(gmp.shortToken).safeTransfer(feeConfiguration.feeReceiver, fee);
            userShortAmountAfterFee = extraData.toLeverageUser - fee;
        } else {
            userShortAmountAfterFee = extraData.toLeverageUser;
        }

        IERC20Upgradeable(gmp.shortToken).safeTransfer(wr.user, userShortAmountAfterFee);

        _positionInfo.closedPositionValue = wr.returnedUSDC;
        // _positionInfo.closePNL = _returnedUSDC;
        _positionInfo.closed = true;
        _positionInfo.position = 0;
        pb.longDebtValue = 0;
        pb.shortDebtValue = 0;
        wr.success = true;

        emit WithdrawalFulfilled(
            _positionInfo.user,
            userShortAmountAfterFee,
            block.timestamp,
            wr.returnedUSDC,
            extraData.waterProfit,
            extraData.leverageUserProfit,
            extraData.longToken,
            positionID,
            gmMarketAmount
        );
        return (true);
    }

    function fulfillCancelDeposit(address longToken) external onlyHandler {
        GMXPoolAddresses memory gmp = gmxPoolAddresses[longToken];
        IERC20Upgradeable(gmp.longToken).safeTransfer(msg.sender, IERC20MetadataUpgradeable(gmp.longToken).balanceOf(address(this)));
        IERC20Upgradeable(gmp.shortToken).safeTransfer(msg.sender, IERC20MetadataUpgradeable(gmp.shortToken).balanceOf(address(this)));
    }

    function fulfillCancelWithdrawal(bytes32 key) external onlyHandler {
        // WithdrawRecord memory wr = withdrawRecord[key];
        inCloseProcess[withdrawRecord[key].user][withdrawRecord[key].positionID] = false;
    }

    function requestLiquidatePosition(address _user, uint256 _positionID) external payable nonReentrant {
        PositionInfo storage _positionInfo = positionInfo[_user][_positionID];
        GMXPoolAddresses memory gmp = gmxPoolAddresses[_positionInfo.longToken];
        _actualizeExtraDebt(gmp, _positionID, _user);
        require(!_positionInfo.liquidated, "Already liquidated");
        require(_positionInfo.user != address(0), "Request !exist");
        (uint256 currentDTV, , ) = getUpdatedDebt(_positionID, _user);
        require(currentDTV >= (DTVLimit * DTVSlippage) / 1000, "Threshold !reached");
        uint256 assetToBeLiquidated = _positionInfo.position;

        IExchangeRouter.CreateWithdrawalParams memory params = _sendTokenAndCreateWithdrawalParams(gmp, assetToBeLiquidated);

        bytes32 key = IExchangeRouter(gmxAddresses.exchangeRouter).createWithdrawal(params);

        WithdrawRecord storage wr = withdrawRecord[key];
        wr.user = _user;
        wr.positionID = _positionID;
        wr.isLiquidation = true;
        wr.liquidator = msg.sender;
        wr.longToken = _positionInfo.longToken;
        userWithdrawKeyRecords[_user].push(key);
    }

    function fulfillLiquidation(bytes32 _key, uint256 _returnedLongAmount, uint256 _returnedUSDC) external onlyHandler returns (bool) {
        WithdrawRecord storage wr = withdrawRecord[_key];
        PositionInfo storage _positionInfo = positionInfo[wr.user][wr.positionID];
        PositionDebt memory pb = positionDebt[wr.user][wr.positionID];
        GMXPoolAddresses memory gmp = gmxPoolAddresses[wr.longToken];
        wr.returnedUSDC = _returnedUSDC;
        _handlePODToken(wr.user, _positionInfo.position);
        require(!_positionInfo.liquidated, "Already liquidated");
        uint256 gmTokenWithdrawnAmount = _positionInfo.position;

        if (_returnedUSDC > pb.shortDebtValue) {
            wr.returnedUSDC -= pb.shortDebtValue;

            uint256 liquidatorReward = (wr.returnedUSDC * feeConfiguration.liquidatorsRewardPercentage) / strategyMisc.MAX_BPS;

            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(wr.liquidator, liquidatorReward);

            uint256 leftovers = wr.returnedUSDC - liquidatorReward;
            uint256 shortTokenAmountAfterLiquidatorReward;
            uint256 amountOut;
            if (leftovers > pb.shortDebtValue) {
                uint256 equalShareBetweenShortAndLongVault = (leftovers - pb.shortDebtValue) / 2;
                shortTokenAmountAfterLiquidatorReward = pb.shortDebtValue + equalShareBetweenShortAndLongVault;
                // transfer equalShareBetweenShortAndLongVault of short token to vodka handler
                IERC20Upgradeable(gmp.shortToken).safeTransfer(strategyAddresses.VodkaHandler, equalShareBetweenShortAndLongVault);
                amountOut = IVodkaV2GMXHandler(strategyAddresses.VodkaHandler).executeSwap(
                    equalShareBetweenShortAndLongVault,
                    gmp.shortToken,
                    gmp.longToken,
                    address(this)
                );
            } else {
                shortTokenAmountAfterLiquidatorReward = pb.shortDebtValue + leftovers;
            }

            _settleWaterDebt(_key, shortTokenAmountAfterLiquidatorReward, _returnedLongAmount + amountOut);
        } else {
            _settleWaterDebt(_key, _returnedUSDC, _returnedLongAmount);
        }

        _positionInfo.liquidated = true;
        _positionInfo.closed = true;
        _positionInfo.position = 0;

        emit Liquidation(msg.sender, wr.user, wr.positionID, gmTokenWithdrawnAmount, wr.returnedUSDC, block.timestamp);
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

    // function _gmxSendToken(GMXPoolAddresses memory gmp, uint256 _position, uint256 _value) internal {
    //     IERC20Upgradeable(gmp.marketToken).approve(gmxAddresses.gmxRouter, _position);
    //     IExchangeRouter(gmxAddresses.exchangeRouter).sendWnt{ value: _value }(gmxAddresses.withdrawVault, _value);
    //     IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(gmp.marketToken, gmxAddresses.withdrawVault, _position);
    // }

    function _settleWaterDebt(bytes32 _key, uint256 _shortTokenValue, uint256 _longTokenValue) internal {
        WithdrawRecord memory wr = withdrawRecord[_key];
        PositionDebt memory pb = positionDebt[wr.user][wr.positionID];
        GMXPoolAddresses memory gmp = gmxPoolAddresses[wr.longToken];
        IERC20Upgradeable(gmp.shortToken).safeIncreaseAllowance(gmp.shortTokenVault, _shortTokenValue);
        IERC20Upgradeable(gmp.longToken).safeIncreaseAllowance(gmp.longTokenVault, _longTokenValue);
        IWater(gmp.shortTokenVault).repayDebt(pb.shortDebtValue, _shortTokenValue);
        IWater(gmp.longTokenVault).repayDebt(pb.longDebtValue, _longTokenValue);
    }

    function _sendTokenAndCreateWithdrawalParams(GMXPoolAddresses memory gmp, uint256 assetToBeLiquidated) internal returns(IExchangeRouter.CreateWithdrawalParams memory) {
        IERC20Upgradeable(gmp.marketToken).approve(gmxAddresses.gmxRouter, assetToBeLiquidated);
        IExchangeRouter(gmxAddresses.exchangeRouter).sendWnt{ value: msg.value }(gmxAddresses.withdrawVault, msg.value);
        IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(gmp.marketToken, gmxAddresses.withdrawVault, assetToBeLiquidated);
        return IExchangeRouter.CreateWithdrawalParams({
            receiver: strategyAddresses.VodkaHandler,
            callbackContract: strategyAddresses.VodkaHandler,
            uiFeeReceiver: msg.sender,
            market: gmp.marketToken,
            longTokenSwapPath: new address[](0),
            shortTokenSwapPath: new address[](0),
            minLongTokenAmount: 0,
            minShortTokenAmount: 0,
            shouldUnwrapNativeToken: false,
            executionFee: feeConfiguration.gmxOpenCloseFees,
            callbackGasLimit: 2000000
        });
    }

    function _actualizeExtraDebt(GMXPoolAddresses memory gmp, uint256 _positionID, address _user) internal {
        PositionDebt storage pb = positionDebt[_user][_positionID];

        uint256 previousLongTokenVaultDA = userDebtAdjustmentValue[_user][_positionID].longDebtValue;
        uint256 previousShortTokenVaultDA = userDebtAdjustmentValue[_user][_positionID].shortDebtValue;

        uint256 longTokenDebtAdjustment = debtAdjustmentValues[gmp.longTokenVault].debtAdjustment;
        uint256 shortTokenDebtAdjustment = debtAdjustmentValues[gmp.shortTokenVault].debtAdjustment;

        if (longTokenDebtAdjustment > previousLongTokenVaultDA) {
            pb.longDebtValue = (pb.longDebtValue * longTokenDebtAdjustment) / previousLongTokenVaultDA;
            userDebtAdjustmentValue[_user][_positionID].longDebtValue = longTokenDebtAdjustment;
        }

        if (shortTokenDebtAdjustment > previousShortTokenVaultDA) {
            pb.shortDebtValue = (pb.shortDebtValue * shortTokenDebtAdjustment) / previousShortTokenVaultDA;
            userDebtAdjustmentValue[_user][_positionID].shortDebtValue = shortTokenDebtAdjustment;
        }
    }

    function _convertGMXMarketToUSDC(uint256 _amount, uint256 _GMXMarketPrice) internal pure returns (uint256) {
        return ((_amount * _GMXMarketPrice) / (10 ** 18)) / 1e12;
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
        } else {
            _burn(_user, position);
        }
    }

    function _payWaterProfits(uint256 _waterProfit, address longToken, address shortToken) internal {
        // with a ratio of 50% to longTokenVault and 50% to shortTokenVault
        uint256 longTokenWaterProfit = _waterProfit / 2;
        uint256 shortTokenWaterProfit = _waterProfit - longTokenWaterProfit;
        // transfer longTokenWaterProfit to vodka handler for swap
        IERC20Upgradeable(shortToken).safeTransfer(strategyAddresses.VodkaHandler, longTokenWaterProfit);
        // swap longTokenWaterProfit to longToken
        uint256 amountOut = IVodkaV2GMXHandler(strategyAddresses.VodkaHandler).executeSwap(
            longTokenWaterProfit,
            shortToken,
            longToken,
            address(this)
        );
        IERC20Upgradeable(longToken).safeTransfer(feeConfiguration.longTokenWaterFeeReceiver, amountOut);
        IERC20Upgradeable(shortToken).safeTransfer(feeConfiguration.shortTokenWaterFeeReceiver, shortTokenWaterProfit);
    }

    receive() external payable {
        require(msg.sender == gmxAddresses.depositVault || msg.sender == gmxAddresses.withdrawVault, "Not gmx");
        payable(IVodkaV2GMXHandler(strategyAddresses.VodkaHandler).tempPayableAddress()).transfer(address(this).balance);
    }
}

