// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IRumVault {
    function getUtilizationRate() external view returns (uint256);

    function burn(uint256 amount) external;

    function getAggregatePosition(address user) external view returns (uint256);

    function handleAndCompoundRewards(address[] calldata pools, address[][] calldata rewarder) external returns (uint256);

    struct PositionInfo {
        uint256 deposit; // total amount of deposit
        uint256 position; // position size
        uint256 buyInPrice; // hlp buy in price
        uint256 leverageAmount;
        uint256 debtAdjustmentValue;
        address liquidator; //address of the liquidator
        address user; // user that created the position
        uint32 positionId;
        uint16 leverageMultiplier; // leverage used
        bool isLiquidated; // true if position was liquidated
        bool isClosed;
    }

    struct DepositRecord {
        address user;
        uint256 depositedAmount;
        uint256 leverageAmount;
        uint256 receivedHLP;
        // uint256 feesPaid;
        uint16 leverageMultiplier;
        bool isOrderCompleted;
        uint256 minOut;
    }

    struct WithdrawRecord {
        uint256 positionID;
        address user;
        bool isOrderCompleted;
        bool isLiquidation;
        uint256 minOut;
        uint256 fullDebtValue;
        uint256 returnedUSDC;
        address liquidator;
    }

    struct FeeConfiguration {
        address feeReceiver;
        uint256 withdrawalFee;
        address waterFeeReceiver;
        uint256 liquidatorsRewardPercentage;
        uint256 fixedFeeSplit;
        uint256 slippageTolerance;
        uint256 hlpFee;
    }

    struct StrategyAddresses {
        address USDC;
        address WETH;
        address hmxCalculator;
        address hlp;
        address hlpLiquidityHandler;
        address hlpStaking; // 0x6eE7520a92a703C4Fda875B45Cccb2c273C65a35
        address hlpCompounder; // 0x8E5D083BA7A46f13afccC27BFB7da372E9dFEF22
        //contract deployed by us:
        address water;
        address MasterChef;
        address hlpRewardHandler;
    }

    struct KeeperInfo {
        address keeper;
        uint256 keeperFee;
    }

    struct DebtToValueRatioInfo {
        uint256 valueInUSDC;
        uint256 debtAndProfitToWater;
    }

    struct DebtAdjustmentValues {
        uint256 debtAdjustment;
        uint256 time;
        uint256 debtValueRatio;
    }

    struct ExtraData {
        uint256 debtAndProfittoWater;
        uint256 toLeverageUser;
        uint256 waterProfit;
        uint256 leverageUserProfit;
        uint256 positionPreviousValue;
        uint256 profits;
        uint256 returnedValue;
        uint256 orderId;
    }

    /** --------------------- Event --------------------- */
    event StrategyContractsChanged(
        address USDC,
        address hmxCalculator,
        address hlpLiquidityHandler,
        address hlpStaking,
        address hlpCompounder,
        address water,
        address MasterChef,
        address WETH,
        address hlp,
        address hlpRewardHandler,
        address keeper
    );
    event DTVLimitSet(uint256 DTVLimit, uint256 DTVSlippage);
    event RequestedOpenPosition(address indexed user, uint256 amount, uint256 time, uint256 orderId);

    event FulfilledOpenPosition(
        address indexed user,
        uint256 depositAmount,
        uint256 hlpAmount,
        uint256 time,
        uint32 positionId,
        uint256 hlpPrice,
        uint256 orderId
    );
    event RequestedClosePosition(address indexed user, uint256 amount, uint256 time, uint256 orderId, uint32 positionId);

    event FulfilledClosePosition(
        address indexed user,
        uint256 amount,
        uint256 time,
        uint256 hlpAmount,
        uint256 profits,
        uint256 hlpPrice,
        uint256 positionId,
        uint256 orderId
    );

    event ProtocolFeeChanged(
        address newFeeReceiver,
        uint256 newWithdrawalFee,
        address newWaterFeeReceiver,
        uint256 liquidatorsRewardPercentage,
        uint256 fixedFeeSplit,
        uint256 keeperFee
    );

    event SetAllowedClosers(address indexed closer, bool allowed);
    event SetAllowedSenders(address indexed sender, bool allowed);
    event SetBurner(address indexed burner, bool allowed);
    event UpdateMaxAndMinLeverage(uint256 maxLeverage, uint256 minLeverage);
    event Liquidated(address indexed user, uint256 indexed positionId, address liquidator, uint256 amount, uint256 reward);
    event USDCHarvested(uint256 amount);
    event OpenPositionCancelled(address indexed user, uint256 amount, uint256 time, uint256 orderId);
    event ClosePositionCancelled(address indexed user, uint256 amount, uint256 time, uint256 orderId, uint256 positionId);
}

