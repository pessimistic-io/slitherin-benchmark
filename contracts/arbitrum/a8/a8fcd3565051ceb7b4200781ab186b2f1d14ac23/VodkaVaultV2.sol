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

interface IWater {
    function lend(uint256 _amount) external returns (bool);

    function repayDebt(uint256 leverage, uint256 debtValue) external;

    function getTotalDebt() external view returns (uint256);

    function updateTotalDebt(uint256 profit) external returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function balanceOfUSDC() external view returns (uint256);
}

interface IVodkaV2GMXHandler {
    function getMarketTokenPrice(
        address longToken,
        bytes32 pnlFactorType,
        bool maximize
    ) external view returns (int256, uint256, uint256, uint256);

    function getEstimatedMarketTokenPrice(
        address _longToken
    ) external view returns (int256, uint256, uint256, uint256);

    function setTempPayableAddress(address _user) external;

    function tempPayableAddress() external view returns (address);
}

contract VodkaVaultV2 is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC20BurnableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;
    using MathUpgradeable for uint128;

    struct PositionInfo {
        uint256 deposit; // total amount of deposit
        uint256 position; // position size original + leverage
        uint256 price; // GMXMarket price
        uint256 closedPositionValue; // value of position when closed
        uint256 closePNL;
        uint256 leverageAmount; //borrowed amount
        address user; // user that created the position
        uint32 positionId;
        address liquidator; //address of the liquidator
        uint16 leverageMultiplier; // leverage multiplier, 2000 = 2x, 10000 = 10x
        bool closed;
        bool liquidated; // true if position was liquidated
        address longToken;
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
        uint256 leverageAmount;
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
    }

    struct StrategyAddresses {
        address USDC;
        address MasterChef;
        address WaterContract;
        address VodkaHandler;
        address WETH;
    }

    struct DebtAdjustmentValues {
        uint256 debtAdjustment;
        uint256 time;
        uint256 debtValueRatio;
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
    address public keeper;

    uint256 private DECIMAL;
    uint256 private MAX_BPS;
    uint256 public DTVLimit;
    uint256 public DTVSlippage;

    mapping(address => PositionInfo[]) public positionInfo;
    mapping(bytes32 => DepositRecord) public depositRecord;
    mapping(address => bytes32[]) public userDepositKeyRecords;
    mapping(bytes32 => WithdrawRecord) public withdrawRecord;
    mapping(address => bytes32[]) public userWithdrawKeyRecords;
    mapping(address => bool) public allowedSenders;
    mapping(address => bool) public burner;
    mapping(address => bool) public isUser;
    mapping(address => bool) public isWhitelistedAsset;
    mapping(address => GMXPoolAddresses) public gmxPoolAddresses;
    mapping(address => mapping(uint256 => uint256))
        public userDebtAdjustmentValue;
    mapping(address => mapping(uint256 => uint256)) public positionLeftoverDebt;
    mapping(address => mapping(uint256 => uint256)) public positionOriginalDebt;
    mapping(address => mapping(uint256 => bool)) public inCloseProcess;

    uint256[50] private __gaps;
    

    modifier InvalidID(uint256 positionId, address user) {
        require(
            positionId < positionInfo[user].length,
            "Vodka: positionID is not valid"
        );
        _;
    }

    modifier onlyBurner() {
        require(burner[msg.sender], "Not allowed to burn");
        _;
    }

    modifier onlyHandler() {
        require(
            msg.sender == strategyAddresses.VodkaHandler,
            "Not allowed to burn"
        );
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
    event Liquidated(
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
    event RequestFulfilled(
        address indexed user,
        uint256 openAmount,
        uint256 closedAmount
    );
    event SetAssetWhitelist(
        address indexed asset,
        address longToken,
        address shortToken,
        address marketToken,
        bool status
    );
    event FeeSplitSet(uint256 indexed split);
    event Liquidated(
        address indexed user,
        uint256 indexed positionId,
        address liquidator,
        uint256 amount,
        uint256 reward
    );
    event SetStrategyParams(
        address indexed MasterChef,
        uint256 MCPID,
        address water,
        address VodkaHandler,
        address keeper
    );
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
        require(_water != address(0), "Invalid address");
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

    function setAllowed(
        address _sender,
        bool _allowed
    ) public onlyOwner {
        require(
            _sender != address(0),
            "VodkaV2: Invalid address"
        );
        allowedSenders[_sender] = _allowed;
        emit SetAllowedSenders(_sender, _allowed);
    }

    function setGmxOpenCloseFees(uint256 _gmxOpenCloseFees) public onlyOwner {
        require(
            _gmxOpenCloseFees <= 0.1 ether,
            "GMXOpenCloseFees must be less than 0.1 eth"
        );
        gmxOpenCloseFees = _gmxOpenCloseFees;
        emit GMXOpenCloseFeeSet(_gmxOpenCloseFees);
    }

    //@TODO ADD ONLY OWNER BACK
    function setDTVLimit(uint256 _DTVLimit, uint256 _DTVSlippage) public onlyOwner {
        require(_DTVSlippage <= 1000, "DTVSlippage must be less than 1000");
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
        bool _status
    ) public onlyOwner {
        GMXPoolAddresses storage gmp = gmxPoolAddresses[_asset];
        gmp.longToken = _longToken;
        gmp.shortToken = _shortToken;
        gmp.marketToken = _marketToken;
        gmp.indexToken = _indexToken;
        isWhitelistedAsset[_asset] = _status;

        emit SetAssetWhitelist(
            _asset,
            _longToken,
            _shortToken,
            _marketToken,
            _status
        );
    }

    function setBurner(
        address _burner,
        bool _allowed
    ) public onlyOwner {
        require(
            _burner != address(0),
            "VodkaV2: Invalid address"
        );
        burner[_burner] = _allowed;
        emit SetBurner(_burner, _allowed);
    }

    function setStrategyParams(
        address _MasterChef,
        uint256 _MCPID,
        address _water,
        address _VodkaHandler,
        address _usdc,
        address _keeper
    ) public onlyOwner {
        strategyAddresses.MasterChef = _MasterChef;
        strategyAddresses.WaterContract = _water;
        strategyAddresses.VodkaHandler = _VodkaHandler;
        strategyAddresses.USDC = _usdc;
        MCPID = _MCPID;
        keeper = _keeper;
        emit SetStrategyParams(_MasterChef, _MCPID, _water, _VodkaHandler,_keeper);
    }

    function setMaxAndMinLeverage(
        uint256 _maxLeverage,
        uint256 _minLeverage
    ) public onlyOwner {
        require(
            _maxLeverage >= _minLeverage,
            "Max leverage must be greater than min leverage"
        );
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
    )
        external
        onlyOwner
    {
        require(
            _liquidatorsRewardPercentage <= 10000 &&
            _withdrawalFee <= 1000,
            "Fees must be within bounds"
        );
        feeConfiguration.feeReceiver = _feeReceiver;
        feeConfiguration.withdrawalFee = _withdrawalFee;
        feeConfiguration.waterFeeReceiver = _waterFeeReceiver;
        feeConfiguration
            .liquidatorsRewardPercentage = _liquidatorsRewardPercentage;
        feeConfiguration.fixedFeeSplit = _fixedFeeSplit;

        emit ProtocolFeeChanged(
            _feeReceiver,
            _withdrawalFee,
            _waterFeeReceiver,
            _liquidatorsRewardPercentage
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

        emit GMXAddressesChanged(
            _depositHandler,
            _withdrawalHandler,
            _depositVault,
            _withdrawVault,
            _gmxRouter,
            _exchangeRouter
        );
    }

    function setDebtValueRatio(
        uint256 _debtValueRatio,
        uint256 _timeAdjustment
    ) external onlyOwner {
        require(
            _debtValueRatio <= 1e18,
            "Debt value ratio must be less than 1"
        );
        debtAdjustmentValues.debtValueRatio = _debtValueRatio;
        timeAdjustment = _timeAdjustment;
    }

    function updateDebtAdjustment() external onlyKeeper {
        require(getUtilizationRate() > (DTVLimit), "Utilization rate is not greater than DTVLimit");
        require(block.timestamp - debtAdjustmentValues.time > timeAdjustment, "Time difference is not greater than 72 hours");

        debtAdjustmentValues.debtAdjustment =
            debtAdjustmentValues.debtAdjustment +
            (debtAdjustmentValues.debtAdjustment *
                debtAdjustmentValues.debtValueRatio) /
            1e18;
        debtAdjustmentValues.time = block.timestamp;
    }

    function pause() external onlyOwner {
        _pause();
    }

    /** ----------- View functions ------------- */

    function getEstimatedGMPrice(
        address _longToken
    ) public view returns (uint256) {
        (int256 gmPrice, , , ) = IVodkaV2GMXHandler(
            strategyAddresses.VodkaHandler
        ).getEstimatedMarketTokenPrice(_longToken);
        return uint256(gmPrice);
    }

    function getAllUsers() public view returns (address[] memory) {
        return allUsers;
    }

    function getTotalOpenPosition(address _user) public view returns (uint256) {
        return positionInfo[_user].length;
    }

    function getUtilizationRate() public view returns (uint256) {
        uint256 totalWaterDebt = IWater(strategyAddresses.WaterContract)
            .totalDebt();
        uint256 totalWaterAssets = IWater(strategyAddresses.WaterContract)
            .balanceOfUSDC();
        return
            totalWaterDebt == 0
                ? 0
                : totalWaterDebt.mulDiv(
                    DECIMAL,
                    totalWaterAssets + totalWaterDebt
                );
    }

    function getUpdatedDebt(
        uint256 _positionID,
        address _user
    ) public view returns (uint256, uint256,uint256) {
        PositionInfo memory _positionInfo = positionInfo[_user][_positionID];
        if (_positionInfo.closed || _positionInfo.liquidated) return (0, 0, 0);

        (uint256 currentPosition, ) = getEstimatedCurrentPosition(
            _positionID,
            _positionInfo.position,
            _user
        );
        uint256 owedToWater = _positionInfo.leverageAmount;
        uint256 currentDTV = owedToWater.mulDiv(DECIMAL, currentPosition);

        return (currentDTV, owedToWater, currentPosition);
    }

    function getEstimatedCurrentPosition(
        uint256 _positionID,
        uint256 _shares,
        address _user
    )
        public
        view
        returns (uint256 currentValueInUSDC, uint256 previousValueInUSDC)
    {
        PositionInfo memory _positionInfo = positionInfo[_user][_positionID];

        uint256 userShares = (_shares == 0) ? _positionInfo.position : _shares;

        return (
            _convertGMXMarketToUSDC(
                userShares,
                getEstimatedGMPrice(_positionInfo.longToken)
            ),
            _convertGMXMarketToUSDC(userShares, _positionInfo.price)
        );
    }

    // // for frontend only
    function getCurrentLeverageAmount(uint256 _positionID, address _user) public view returns (uint256,uint256) {
        PositionInfo memory _positionInfo = positionInfo[_user][_positionID];
        uint256 previousDA = userDebtAdjustmentValue[_user][_positionID];
        uint256 userLeverageAmount = _positionInfo.leverageAmount;

        uint256 extraDebt;
        if (debtAdjustmentValues.debtAdjustment > previousDA) {
            userLeverageAmount = userLeverageAmount.mulDiv(debtAdjustmentValues.debtAdjustment, previousDA);
            extraDebt = userLeverageAmount - _positionInfo.leverageAmount;
        } else {
            extraDebt = positionLeftoverDebt[_user][_positionID];
        }
        return (userLeverageAmount,extraDebt);
    }

    /** ----------- User functions ------------- */

    function requestOpenPosition(
        uint256 _amount,
        uint16 _leverage,
        address _shortAsset
    ) external payable whenNotPaused nonReentrant {
        require(
            _leverage >= MIN_LEVERAGE && _leverage <= MAX_LEVERAGE,
            "VodkaV2: Invalid leverage"
        );
        require(_amount > 0, "VodkaV2: amount must be greater than zero");
        require(
            isWhitelistedAsset[_shortAsset],
            "VodkaV2: asset is not whitelisted"
        );

        IERC20Upgradeable(strategyAddresses.USDC).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        uint256 amount = _amount;

        // get leverage amount
        uint256 leveragedAmount = amount.mulDiv(_leverage, 1000) - amount;
        bool status = IWater(strategyAddresses.WaterContract).lend(
            leveragedAmount
        );
        require(status, "Water: Lend failed");
        // add leverage amount to amount
        uint256 xAmount = amount + leveragedAmount;

        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(
            gmxAddresses.gmxRouter,
            xAmount
        );
        IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(
            strategyAddresses.USDC,
            gmxAddresses.depositVault,
            xAmount
        );
        IExchangeRouter(gmxAddresses.exchangeRouter).sendWnt{value: msg.value}(
            gmxAddresses.depositVault,
            msg.value
        );

        GMXPoolAddresses memory gmp = gmxPoolAddresses[_shortAsset];

        IExchangeRouter.CreateDepositParams memory params = IExchangeRouter
            .CreateDepositParams({
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

        bytes32 key = IExchangeRouter(gmxAddresses.exchangeRouter)
            .createDeposit(params);

        DepositRecord storage dr = depositRecord[key];

        dr.leverageAmount = leveragedAmount;
        dr.depositedAmount = amount;
        dr.feesPaid = msg.value;
        dr.user = msg.sender;
        dr.leverageMultiplier = _leverage;
        dr.longToken = gmp.longToken;
        userDepositKeyRecords[msg.sender].push(key);
    }

    function fulfillOpenPosition(
        bytes32 key,
        uint256 _receivedTokens
    ) public onlyHandler returns (bool) {
        DepositRecord storage dr = depositRecord[key];
        dr.receivedMarketTokens = _receivedTokens;
        address user = dr.user;

        IVodkaV2GMXHandler(strategyAddresses.VodkaHandler)
            .setTempPayableAddress(user);

        PositionInfo memory _positionInfo = PositionInfo({
            user: dr.user,
            deposit: dr.depositedAmount,
            leverageMultiplier: dr.leverageMultiplier,
            position: dr.receivedMarketTokens,
            price: ((dr.depositedAmount * dr.leverageMultiplier/1000) * 1e12) * 1e18 / dr.receivedMarketTokens,
            liquidated: false,
            closedPositionValue: 0,
            liquidator: address(0),
            closePNL: 0,
            leverageAmount: dr.leverageAmount,
            positionId: uint32(positionInfo[user].length),
            closed: false,
            longToken: dr.longToken
        });

        if (isUser[user] == false) {
            isUser[user] = true;
            allUsers.push(user);
        }

        positionOriginalDebt[dr.user][positionInfo[user].length] = dr
            .leverageAmount;
        userDebtAdjustmentValue[dr.user][
            positionInfo[user].length
        ] = debtAdjustmentValues.debtAdjustment;

        positionInfo[user].push(_positionInfo);
        _mint(user, dr.receivedMarketTokens);

        dr.success = true;

        emit Deposited(
            user,
            _positionInfo.deposit,
            block.timestamp,
            dr.receivedMarketTokens,
            dr.longToken,
            positionInfo[user].length
        );

        return true;
    }

    function requestClosePosition(
        uint256 _positionID,
        address _user
    ) external payable InvalidID(_positionID, _user) nonReentrant {
        PositionInfo storage _positionInfo = positionInfo[_user][_positionID];
        require(
            !_positionInfo.liquidated || !_positionInfo.closed,
            "VodkaV2: position is closed or liquidated"
        );
        require(
            _positionInfo.position > 0,
            "VodkaV2: position is not enough to close"
        );
        require(
            msg.sender == _positionInfo.user,
            "VodkaV2: not allowed to close position"
        );
        require(
            !inCloseProcess[_user][_positionID],
            "VodkaV2: close position request already ongoing"
        );

        GMXPoolAddresses memory gmp = gmxPoolAddresses[_positionInfo.longToken];
        uint256 extraDebt;
        (_positionInfo.leverageAmount, extraDebt) = _actualizeExtraDebt(
            _positionID,
            _user
        );
        (uint256 currentDTV, ,) = getUpdatedDebt(_positionID, _user);
        if (currentDTV >= DTVLimit * DTVSlippage / 1000) {
            revert("Wait for liquidation");
        }

        IERC20Upgradeable(gmp.marketToken).approve(
            gmxAddresses.gmxRouter,
            _positionInfo.position
        );
        IExchangeRouter(gmxAddresses.exchangeRouter).sendWnt{value: msg.value}(
            gmxAddresses.withdrawVault,
            msg.value
        );
        IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(
            gmp.marketToken,
            gmxAddresses.withdrawVault,
            _positionInfo.position
        );

        IExchangeRouter.CreateWithdrawalParams memory params = IExchangeRouter
            .CreateWithdrawalParams({
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

        bytes32 key = IExchangeRouter(gmxAddresses.exchangeRouter)
            .createWithdrawal(params);

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
        uint256 _returnedUSDC
    ) public onlyHandler returns (bool) {
        WithdrawRecord storage wr = withdrawRecord[_key];
        PositionInfo storage _positionInfo = positionInfo[wr.user][
            wr.positionID
        ];
        ExtraData memory extraData;
        require(
            inCloseProcess[wr.user][wr.positionID],
            "VodkaV2: close position request not ongoing"
        );
        _burn(wr.user, _positionInfo.position);
        uint256 positionID = wr.positionID;
        uint256 gmMarketAmount = wr.gmTokenWithdrawnAmount;
        wr.fullDebtValue = _positionInfo.leverageAmount;
        extraData.longToken = wr.longToken;
        wr.returnedUSDC = _returnedUSDC;
        extraData.positionPreviousValue = _convertGMXMarketToUSDC(
            _positionInfo.position,
            _positionInfo.price
        );
        extraData.returnedValue = _returnedUSDC;

        IVodkaV2GMXHandler(strategyAddresses.VodkaHandler)
            .setTempPayableAddress(wr.user);

        if (_returnedUSDC > extraData.positionPreviousValue) {
            extraData.profits = _returnedUSDC - extraData.positionPreviousValue;
        }

        uint256 waterRepayment;
        (uint256 waterProfits, uint256 leverageUserProfits) = _getProfitSplit(
            extraData.profits,
            _positionInfo.leverageMultiplier
        );

        if (extraData.returnedValue < (wr.fullDebtValue + waterProfits)) {
            _positionInfo.liquidator = msg.sender;
            _positionInfo.liquidated = true;
            waterRepayment = extraData.returnedValue;
        } else {
            extraData.toLeverageUser = (extraData.returnedValue - wr.fullDebtValue - extraData.profits) + leverageUserProfits;
            waterRepayment = extraData.returnedValue - extraData.toLeverageUser - waterProfits;

            _positionInfo.closed = true;
            _positionInfo.closePNL = extraData.returnedValue;
            _positionInfo.position = 0;
            _positionInfo.leverageAmount = 0;
        }

        if (waterProfits > 0) {
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(
                feeConfiguration.waterFeeReceiver,
                waterProfits
            );
        }

        uint256 debtPortion = positionOriginalDebt[wr.user][positionID];
        positionOriginalDebt[wr.user][positionID] = 0;
        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(
            strategyAddresses.WaterContract,
            waterRepayment
        );
        IWater(strategyAddresses.WaterContract).repayDebt(
            debtPortion,
            waterRepayment
        );

        if (_positionInfo.liquidated) {
            return (false);
        }

        uint256 amountAfterFee;
        if (feeConfiguration.withdrawalFee > 0) {
            uint256 fee = extraData.toLeverageUser.mulDiv(
                feeConfiguration.withdrawalFee,
                MAX_BPS
            );
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(
                feeConfiguration.feeReceiver,
                fee
            );
            amountAfterFee = extraData.toLeverageUser - fee;
        } else {
            amountAfterFee = extraData.toLeverageUser;
        }

        IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(
            wr.user,
            amountAfterFee
        );

        _positionInfo.closedPositionValue += wr.returnedUSDC;

        emit WithdrawalFulfilled(
            _positionInfo.user,
            amountAfterFee,
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

    function requestLiquidatePosition(
        address _user,
        uint256 _positionID
    ) external payable nonReentrant {
        PositionInfo storage _positionInfo = positionInfo[_user][_positionID];
        (_positionInfo.leverageAmount, ) = _actualizeExtraDebt(_positionID, _user);
        require(!_positionInfo.liquidated, "VodkaV2: Already liquidated");
        require(
            _positionInfo.user != address(0),
            "VodkaV2: liquidation request does not exist"
        );
        (uint256 currentDTV, ,) = getUpdatedDebt(_positionID, _user);
        require(
            currentDTV >= DTVLimit * DTVSlippage / 1000,
            "Liquidation threshold not reached yet"
        );
        uint256 assetToBeLiquidated = _positionInfo.position;

        GMXPoolAddresses memory gmp = gmxPoolAddresses[_positionInfo.longToken];

        IERC20Upgradeable(gmp.marketToken).approve(
            gmxAddresses.gmxRouter,
            assetToBeLiquidated
        );
        IExchangeRouter(gmxAddresses.exchangeRouter).sendWnt{value: msg.value}(
            gmxAddresses.withdrawVault,
            msg.value
        );
        IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(
            gmp.marketToken,
            gmxAddresses.withdrawVault,
            assetToBeLiquidated
        );

        IExchangeRouter.CreateWithdrawalParams memory params = IExchangeRouter
            .CreateWithdrawalParams({
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

        bytes32 key = IExchangeRouter(gmxAddresses.exchangeRouter)
            .createWithdrawal(params);

        WithdrawRecord storage wr = withdrawRecord[key];
        wr.gmTokenWithdrawnAmount = assetToBeLiquidated;
        wr.user = _user;
        wr.positionID = _positionID;
        wr.isLiquidation = true;
        wr.liquidator = msg.sender;
        wr.longToken = _positionInfo.longToken;

        userWithdrawKeyRecords[_user].push(key);
    }

    function fulfillLiquidation(
        bytes32 _key,
        uint256 _returnedUSDC
    ) external onlyHandler returns (bool) {
        WithdrawRecord storage wr = withdrawRecord[_key];
        PositionInfo storage _positionInfo = positionInfo[wr.user][
            wr.positionID
        ];
        wr.returnedUSDC = _returnedUSDC;
        _handlePODToken(wr.user, _positionInfo.position);
        uint256 debtPortion = positionOriginalDebt[wr.user][wr.positionID];
        if (wr.returnedUSDC >= debtPortion) {
            
            wr.returnedUSDC -= debtPortion;

            uint256 liquidatorReward = wr.returnedUSDC.mulDiv(feeConfiguration.liquidatorsRewardPercentage,MAX_BPS);
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(wr.liquidator,liquidatorReward);

            uint256 leftovers = wr.returnedUSDC - liquidatorReward;
            
            IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(
                strategyAddresses.WaterContract,
                leftovers + debtPortion
            );
            IWater(strategyAddresses.WaterContract).repayDebt(debtPortion,leftovers + debtPortion);

        } else {
            IWater(strategyAddresses.WaterContract).repayDebt(debtPortion,wr.returnedUSDC);
        }

        _positionInfo.liquidated = true;
        _positionInfo.closed = true;
        _positionInfo.position = 0;
        _positionInfo.leverageAmount = 0;

        emit Liquidated(
            msg.sender,
            wr.user,
            wr.positionID,
            wr.gmTokenWithdrawnAmount,
            wr.returnedUSDC,
            block.timestamp
        );
        return (true);
    }

    /** ----------- Token functions ------------- */

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        require(
            allowedSenders[from] ||
                allowedSenders[to] ||
                allowedSenders[spender],
            "ERC20: transfer not allowed"
        );
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address ownerOf = _msgSender();
        require(
            allowedSenders[ownerOf] || allowedSenders[to],
            "ERC20: transfer not allowed"
        );
        _transfer(ownerOf, to, amount);
        return true;
    }

    function burn(uint256 amount) public virtual override onlyBurner {
        _burn(_msgSender(), amount);
    }

    /** ----------- Internal functions ------------- */

    function _actualizeExtraDebt(
        uint256 _positionID,
        address _user
    ) internal returns (uint256, uint256) {
        PositionInfo memory _positionInfo = positionInfo[_user][_positionID];
        uint256 previousDA = userDebtAdjustmentValue[_user][_positionID];
        uint256 userLeverageAmount = _positionInfo.leverageAmount;

        if (debtAdjustmentValues.debtAdjustment > previousDA) {
            userLeverageAmount = userLeverageAmount.mulDiv(
                debtAdjustmentValues.debtAdjustment,
                previousDA
            );
            uint256 extraDebt = userLeverageAmount -
                _positionInfo.leverageAmount;
            positionLeftoverDebt[_user][_positionID] += extraDebt;
            userDebtAdjustmentValue[_user][_positionID] = debtAdjustmentValues
                .debtAdjustment;
        }
        return (userLeverageAmount, positionLeftoverDebt[_user][_positionID]);
    }

    function _getProfitSplit(
        uint256 _profit,
        uint256 _leverage
    ) internal view returns (uint256, uint256) {
        if (_profit == 0) {
            return (0, 0);
        }
        uint256 split = (feeConfiguration.fixedFeeSplit *
            _leverage +
            (feeConfiguration.fixedFeeSplit * 10000)) / 100;
        uint256 toWater = (_profit * split) / 10000;
        uint256 toVodkaV2User = _profit - toWater;

        return (toWater, toVodkaV2User);
    }

    function _convertGMXMarketToUSDC(
        uint256 _amount,
        uint256 _GMXMarketPrice
    ) internal pure returns (uint256) {
        return _amount.mulDiv(_GMXMarketPrice, (10 ** 18)) / 1e12;
    }

    function _handlePODToken(address _user, uint256 position) internal {
        uint256 userAmountStaked;
        if (strategyAddresses.MasterChef != address(0)) {
            (userAmountStaked, ) = IMasterChef(strategyAddresses.MasterChef)
                .userInfo(MCPID, _user);
            if (userAmountStaked > 0) {
                uint256 amountToBurnFromUser;
                if (userAmountStaked > position) {
                    amountToBurnFromUser = position;
                } else {
                    amountToBurnFromUser = userAmountStaked;
                    uint256 _position = position - userAmountStaked;
                    _burn(_user, _position);
                }
                IMasterChef(strategyAddresses.MasterChef).unstakeAndLiquidate(
                    MCPID,
                    _user,
                    amountToBurnFromUser
                );
            }
            if (userAmountStaked == 0) {
                _burn(_user, position);
            }
        } else {
            _burn(_user, position);
        }
    }

    receive() external payable {
        require(
            msg.sender == gmxAddresses.depositVault ||
                msg.sender == gmxAddresses.withdrawVault,
            "Not GMX"
        );

        payable(
            IVodkaV2GMXHandler(strategyAddresses.VodkaHandler)
                .tempPayableAddress()
        ).transfer(address(this).balance);
    }
}

