// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IDepositCallbackReceiver.sol";
import "./IWithdrawalCallbackReceiver.sol";

import "./Deposit.sol";
import "./Withdrawal.sol";
import "./EventUtils.sol";
import "./IOracle.sol";
import "./Role.sol";

import "./console.sol";

interface IRoleStore {
    function hasRole(address account, bytes32 roleKey) external view returns (bool);
}

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(
        uint80 _roundId
    ) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint deadline;
        uint amountIn;
        uint amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps amountIn of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as ExactInputSingleParams in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint deadline;
        uint amountIn;
        uint amountOutMinimum;
    }

    /// @notice Swaps amountIn of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as ExactInputParams in calldata
    /// @return amountOut The amount of the received token
    function exactInput(ExactInputParams calldata params) external payable returns (uint amountOut);
}

interface IWater {
    function lend(uint256 _amount) external returns (bool);

    function repayDebt(uint256 leverage, uint256 debtValue) external returns (bool);
}

interface IVodkaV2 {
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

    struct GMXPoolAddresses {
        address longToken;
        address shortToken;
        address marketToken;
        address indexToken;
        address longTokenVault;
        address shortTokenVault;
    }

    struct PositionDebt {
        uint256 longDebtValue;
        uint256 shortDebtValue;
    }

    function getStrategyAddresses() external view returns (address[10] memory);

    function fulfillOpenPosition(bytes32 key, uint256 _receivedTokens) external returns (bool);

    function fulfillClosePosition(
        bytes32 key,
        uint256 _returnedLongAmount,
        uint256 _receivedUSDC,
        uint256 _longAmountValue
    ) external returns (bool);

    function fulfillCancelDeposit(address longToken) external;

    function fulfillCancelWithdrawal(bytes32 key) external;

    function fulfillLiquidation(bytes32 _key, uint256 _returnedLongAmount, uint256 _returnedUSDC) external returns (bool);

    function depositRecord(bytes32 key) external view returns (DepositRecord memory);

    function withdrawRecord(bytes32 key) external view returns (WithdrawRecord memory);

    function gmxPoolAddresses(address longToken) external view returns (GMXPoolAddresses memory);

    function positionDebt(address _user, uint256 _positionID) external view returns (PositionDebt memory);

    function positionInfo(address _user, uint256 _positionID) external view returns (PositionInfo memory);

    function getEstimatedCurrentPosition(uint256 _positionID, address _user) external view returns (uint256, uint256);
}

contract VodkaV2GMXHandler is
    IDepositCallbackReceiver,
    IWithdrawalCallbackReceiver,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;
    using MathUpgradeable for uint128;

    struct StrategyAddresses {
        address USDC;
        address WaterContract;
        address VodkaV2;
        address univ3Router;
        address dataStore;
        address oracle;
        address reader;
        address depositHandler;
        address withdrawalHandler;
    }

    struct OrderRefunded {
        uint256 feesRefunded;
        uint256 amountRefunded;
        uint256 longTokenAmountReturned;
        uint256 shortTokenAmountReturned;
        uint256 gmTokensRefunded;
        uint256 depositOrWithdrawal; //0 deposit //1 withdrawal
        bool cancelled;
    }

    struct Data {
        int256 marketTokenPrice;
        bytes32 factorType;
        bool maximize;
        uint256 residualOut;
        uint256 shortTokenAmountReturned;
        uint256 longTokenAmountReturned;
        uint256 longAmountValue;
        uint256 residualConversion;
    }

    StrategyAddresses public strategyAddresses;

    mapping(bytes32 => OrderRefunded) public orderRefunded;
    mapping(address => bytes32[]) public userRefunds;
    mapping(address => address) public chainlinkOracle;

    address public tempPayableAddress;
    address public RoleStore;

    uint256[50] private __gaps;
    uint256 private constant GRACE_PERIOD_TIME = 3600; // 1 hour

    address arbitrumSequencer;

    event StrategyParamsSet(
        address univ3Router,
        address dataStore,
        address oracle,
        address reader,
        address depositHandler,
        address withdrawalHandler
    );

    event ChainlinkOracleSet(address token, address oracle);
    event RepayDepositFailure(address user, uint256 amount, string errorMessage, string stackTrace);

    modifier zeroAddress(address addr) {
        require(addr != address(0), "Zero address");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _USDC, address _VodkaV2) external initializer {
        strategyAddresses.VodkaV2 = _VodkaV2;
        strategyAddresses.USDC = _USDC;

        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /** ----------- Change onlyOwner functions ------------- */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setArbitrumSequencer(address _arbitrumSequencer) external onlyOwner {
        arbitrumSequencer = _arbitrumSequencer;
    }

    //function to set all variables setStrategyParams
    function setStrategyParams(
        address _univ3Router,
        address _dataStore,
        address _oracle,
        address _reader,
        address _depositHandler,
        address _withdrawalHandler
    ) external onlyOwner {
        strategyAddresses.univ3Router = _univ3Router;
        strategyAddresses.dataStore = _dataStore;
        strategyAddresses.oracle = _oracle;
        strategyAddresses.reader = _reader;
        strategyAddresses.depositHandler = _depositHandler;
        strategyAddresses.withdrawalHandler = _withdrawalHandler;
        emit StrategyParamsSet(_univ3Router, _dataStore, _oracle, _reader, _depositHandler, _withdrawalHandler);
    }

    function setRoleStore(address _roleStore) external zeroAddress(_roleStore) onlyOwner {
        RoleStore = _roleStore;
    }

    function setChainlinkOracleForAsset(address _token, address _oracle) external onlyOwner {
        require(_token != address(0), "Zero address");
        chainlinkOracle[_token] = _oracle;
        emit ChainlinkOracleSet(_token, _oracle);
    }

    function getLatestData(address _token, bool _inDecimal) public view returns (uint256) {
        // prettier-ignore
        (
            /*uint80 roundID*/,
            int256 sqAnswer,
            uint256 sqStartedAt,
            /*uint256 updatedAt*/,
            /*uint80 answeredInRound*/
        ) = AggregatorV3Interface(arbitrumSequencer).latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = sqAnswer == 0;

        // Make sure the grace period has passed after the
        // sequencer is back up.
        uint256 timeSinceUp = block.timestamp - sqStartedAt;
        require(timeSinceUp > GRACE_PERIOD_TIME, "Grace period not over");

        require(isSequencerUp, "Sequencer is down");

        (, /* uint80 roundID */ int answer /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/, , , ) = AggregatorV3Interface(
            chainlinkOracle[_token]
        ).latestRoundData(); //in 1e8

        uint256 decimalPrice;
        if (_inDecimal) {
            if (_token == strategyAddresses.USDC) {
                decimalPrice = uint256(answer) * 1e10 * 1e6;
            } else {
                decimalPrice = (uint256(answer) * 1e10) / 1e6;
            }
        } else {
            decimalPrice = uint256(answer) * 1e10;
        }

        return decimalPrice;
    }

    function getDepositRecord(bytes32 key) public view returns (IVodkaV2.DepositRecord memory) {
        return IVodkaV2(strategyAddresses.VodkaV2).depositRecord(key);
    }

    function getWithdrawRecord(bytes32 key) public view returns (IVodkaV2.WithdrawRecord memory) {
        return IVodkaV2(strategyAddresses.VodkaV2).withdrawRecord(key);
    }

    function getPositionDebt(address _user, uint256 _positionID) public view returns (IVodkaV2.PositionDebt memory) {
        return IVodkaV2(strategyAddresses.VodkaV2).positionDebt(_user, _positionID);
    }

    function getPositionInfo(address _user, uint256 _positionID) public view returns (IVodkaV2.PositionInfo memory) {
        return IVodkaV2(strategyAddresses.VodkaV2).positionInfo(_user, _positionID);
    }

    function getMarketTokenPrice(address longToken, bytes32 pnlFactorType, bool maximize) public view returns (int256) {
        IVodkaV2.GMXPoolAddresses memory gmp = IVodkaV2(strategyAddresses.VodkaV2).gmxPoolAddresses(longToken);
        Data memory data;
        Market.Props memory market = Market.Props({
            marketToken: gmp.marketToken,
            indexToken: gmp.indexToken,
            longToken: gmp.longToken,
            shortToken: gmp.shortToken
        });
        data.factorType = pnlFactorType;
        data.maximize = maximize;

        Price.Props memory indexTokenPrice = IOracle(strategyAddresses.oracle).getPrimaryPrice(gmp.indexToken);

        Price.Props memory longTokenPrice = IOracle(strategyAddresses.oracle).getPrimaryPrice(gmp.longToken);

        Price.Props memory shortTokenPrice = IOracle(strategyAddresses.oracle).getPrimaryPrice(gmp.shortToken);

        (data.marketTokenPrice, ) = IReader(strategyAddresses.reader).getMarketTokenPrice(
            strategyAddresses.dataStore,
            market,
            indexTokenPrice,
            longTokenPrice,
            shortTokenPrice,
            data.factorType,
            data.maximize
        );

        data.marketTokenPrice = data.marketTokenPrice / 1e12;

        return (data.marketTokenPrice);
    }

    function getEstimatedMarketTokenPrice(address longToken) public view returns (int256) {
        IVodkaV2.GMXPoolAddresses memory gmp = IVodkaV2(strategyAddresses.VodkaV2).gmxPoolAddresses(longToken);
        Market.Props memory market = Market.Props({
            marketToken: gmp.marketToken,
            indexToken: gmp.indexToken,
            longToken: gmp.longToken,
            shortToken: gmp.shortToken
        });

        Price.Props memory indexTokenPrice = Price.Props({
            max: uint256(getLatestData(gmp.indexToken, true)),
            min: uint256(getLatestData(gmp.indexToken, true))
        });

        uint256 index = uint256(getLatestData(gmp.indexToken, true));
        console.log("index", index);

        Price.Props memory longTokenPrice = Price.Props({
            //prettier ignore
            max: uint256(getLatestData(longToken, true)),
            min: uint256(getLatestData(longToken, true))
        });

        uint256 long = uint256(getLatestData(longToken, true));
        console.log("long", long);

        Price.Props memory shortTokenPrice = Price.Props({
            max: uint256(getLatestData(strategyAddresses.USDC, true)),
            min: uint256(getLatestData(strategyAddresses.USDC, true))
        });

        uint256 usdc = uint256(getLatestData(strategyAddresses.USDC, true));
        console.log("usdc", usdc);

        (int256 marketTokenPrice, ) = IReader(strategyAddresses.reader).getMarketTokenPrice(
            strategyAddresses.dataStore,
            market,
            indexTokenPrice,
            longTokenPrice,
            shortTokenPrice,
            keccak256("MAX_PNL_FACTOR_FOR_WITHDRAWALS"),
            false
        );

        console.log("marketTokenPrice", uint256(marketTokenPrice));

        marketTokenPrice = marketTokenPrice / 1e12;
        uint256 mp = uint256(marketTokenPrice);
        console.log("marketTokenPrice", mp);

        return (marketTokenPrice);
    }

    function takeAll(address _inputSsset) public onlyOwner {
        uint256 balance = IERC20Upgradeable(_inputSsset).balanceOf(address(this));
        IERC20Upgradeable(_inputSsset).transfer(msg.sender, balance);
    }

    function _setTempPayableAddress(address _tempPayableAddress) internal {
        tempPayableAddress = _tempPayableAddress;
    }

    /** -----GMX callback functions */
    function afterDepositExecution(bytes32 key, Deposit.Props memory deposit, EventUtils.EventLogData memory eventData) external {
        console.log("afterDepositExecution");
        require(IRoleStore(RoleStore).hasRole(msg.sender, Role.CONTROLLER), "Not proper role");
        console.log("afterDepositExecution");
        IVodkaV2.DepositRecord memory dr = getDepositRecord(key);
        _setTempPayableAddress(dr.user);
        console.log("dr.user", dr.user);
        console.log("eventData.uintItems.items[0].value", eventData.uintItems.items[0].value);

        IVodkaV2(strategyAddresses.VodkaV2).fulfillOpenPosition(key, eventData.uintItems.items[0].value);
    }

    //NEED TO HANDLE REPAY TO THE RELEVANT VAULT
    function afterDepositCancellation(bytes32 key, Deposit.Props memory deposit, EventUtils.EventLogData memory eventData) external {
        require(IRoleStore(RoleStore).hasRole(msg.sender, Role.CONTROLLER), "Not proper role");

        IVodkaV2.DepositRecord memory dr = getDepositRecord(key);
        IVodkaV2.GMXPoolAddresses memory gmp = IVodkaV2(strategyAddresses.VodkaV2).gmxPoolAddresses(dr.longToken);
        OrderRefunded storage or = orderRefunded[key];

        IVodkaV2(strategyAddresses.VodkaV2).fulfillCancelDeposit(gmp.longToken);

        uint256 userDepositAmountReturned = deposit.numbers.initialShortTokenAmount - dr.shortTokenBorrowed;
        IERC20Upgradeable(gmp.longToken).safeIncreaseAllowance(gmp.longTokenVault, dr.longTokenBorrowed);
        IERC20Upgradeable(gmp.shortToken).safeIncreaseAllowance(gmp.shortTokenVault, dr.shortTokenBorrowed);
        IWater(gmp.shortTokenVault).repayDebt(dr.shortTokenBorrowed, dr.shortTokenBorrowed);
        IWater(gmp.longTokenVault).repayDebt(dr.longTokenBorrowed, dr.longTokenBorrowed);

        try IERC20Upgradeable(strategyAddresses.USDC).transfer(dr.user, userDepositAmountReturned) returns (bool success) {
            require(success, "USDC transfer failed");
        } catch Error(string memory errorMessage) {
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(owner(), userDepositAmountReturned);
        }

        // or.feesRefunded = eventData.uintItems.items[0].value;
        or.amountRefunded = dr.depositedAmount;
        or.longTokenAmountReturned = dr.longTokenBorrowed;
        or.shortTokenAmountReturned = dr.shortTokenBorrowed;
        or.cancelled = true;
        or.depositOrWithdrawal = 0;

        userRefunds[dr.user].push(key);
    }

    function afterWithdrawalExecution(bytes32 key, Withdrawal.Props memory withdrawal, EventUtils.EventLogData memory eventData) external {
        require(IRoleStore(RoleStore).hasRole(msg.sender, Role.CONTROLLER), "Not proper role");
        console.log("afterWithdrawalExecution");

        IVodkaV2.WithdrawRecord memory wr = getWithdrawRecord(key);
        IVodkaV2.PositionDebt memory pb = getPositionDebt(wr.user, wr.positionID);
        // IVodkaV2.PositionInfo memory pi = getPositionInfo(wr.user, wr.positionID);
        _setTempPayableAddress(wr.user);
        Data memory data;

        // uint256 longDebtValue = pb.longDebtValue;
        // uint256 shortDebtValue = pb.shortDebtValue;

        uint256 longAmountFromGMX = eventData.uintItems.items[0].value;
        uint256 usdcAmountFromGMX = eventData.uintItems.items[1].value;
        console.log("=====================================");
        console.log("longAmountFromGMX", longAmountFromGMX);
        console.log("usdcAmountFromGMX", usdcAmountFromGMX);
        uint256 totalLongToken;
        uint256 totalShortToken;

        // If USDC received is less than short debt
        // and long tokens received are greater than long debt
        // usdcAmountFromGMX < (shortDebtValue + pi.deposit) &&
        if (longAmountFromGMX > pb.longDebtValue) {
            console.log("longAmountFromGMX > pb.longDebtValue");
            // Calculate long tokens available to swap for Long Token
            uint256 longAvailableToSwap = longAmountFromGMX - pb.longDebtValue;
            totalLongToken = longAmountFromGMX - longAvailableToSwap;
            console.log("longAvailableToSwap", longAvailableToSwap);
            console.log("totalLongToken", totalLongToken);
            // Swap long tokens for USDC and keep debt value borrowed from long token vault
            data.shortTokenAmountReturned = _executeSwap(longAvailableToSwap, wr.longToken, strategyAddresses.USDC, address(this));
            console.log("data.shortTokenAmountReturned", data.shortTokenAmountReturned);
            totalShortToken = usdcAmountFromGMX + data.shortTokenAmountReturned;
            console.log("totalShortToken", totalShortToken);
        }
        /* if (longAmountFromGMX < longDebtValue && usdcAmountFromGMX > (shortDebtValue + pi.deposit)) */
        else {
            console.log("longAmountFromGMX < longDebtValue && usdcAmountFromGMX > (shortDebtValue + pi.deposit)");
            // Calculate short tokens available to swap for short Token
            uint256 shortAvailableToSwap = usdcAmountFromGMX - pb.shortDebtValue;
            console.log("shortAvailableToSwap", shortAvailableToSwap);
            console.log("pb.shortDebtValue", pb.shortDebtValue);
            // Get residual long tokens needed to cover debt
            data.residualOut = pb.longDebtValue - longAmountFromGMX;
            console.log("data.residualOut", data.residualOut);
            console.log("pb.longDebtValue", getLatestData(wr.longToken, true)); 
            console.log("pb.longDebtValue", getLatestData(wr.longToken, false));

            // convert residual to short tokens based on price of short token
            // convert residual to USDC
            // first get the price of long token in pow of 18
            // residualOut is in pow of 18
            data.residualConversion = ((data.residualOut * 1e6 * (getLatestData(wr.longToken, false)) / 1e18 / 1e18));
            // data.residualConversion = ((data.residualOut * 1e6) * 1e18) / getLatestData(strategyAddresses.USDC, true);
            console.log("data.residualConversion", data.residualConversion); 
            // add liquidity fee to the residual conversion
            data.residualConversion = data.residualConversion + (data.residualConversion * 3) / 1000;
            console.log("data.residualConversion", data.residualConversion);
            // If residual conversion greater than available, swap all available
            // Else swap just the residual amount
            if (data.residualConversion > shortAvailableToSwap) {
                console.log("data.residualConversion > shortAvailableToSwap");
                // balance it up from pi.deposit to ensure that the long debt is covered by leverage user deposited amount
                // shortAvailableToSwap = shortAvailableToSwap + (data.residualConversion - shortAvailableToSwap);
                data.longTokenAmountReturned = _executeSwap(shortAvailableToSwap, strategyAddresses.USDC, wr.longToken, address(this));
                totalLongToken = longAmountFromGMX + data.longTokenAmountReturned;
                console.log("totalLongToken", totalLongToken);
                totalShortToken = usdcAmountFromGMX - shortAvailableToSwap;
                console.log("totalShortToken", totalShortToken);
            } else {
                console.log("data.residualConversion < shortAvailableToSwap");
                data.longTokenAmountReturned = _executeSwap(data.residualConversion, strategyAddresses.USDC, wr.longToken, address(this));
                console.log("data.longTokenAmountReturned", data.longTokenAmountReturned); 
                totalLongToken = longAmountFromGMX + data.longTokenAmountReturned;
                console.log("totalLongToken", totalLongToken);
                totalShortToken = usdcAmountFromGMX - data.residualConversion;
                console.log("totalShortToken", totalShortToken);
            }
        }

        data.longAmountValue = (getLatestData(wr.longToken, true) * totalLongToken) / 1e18;
        console.log("data.longAmountValue", data.longAmountValue);
        console.log("estimatePositionProfit(key, longAmountFromGMX, usdcAmountFromGMX)", estimatePositionProfit(key, longAmountFromGMX, usdcAmountFromGMX));
        console.log("==================After all estimation ===================");

        IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(strategyAddresses.VodkaV2, totalShortToken);
        IERC20Upgradeable(wr.longToken).safeTransfer(strategyAddresses.VodkaV2, totalLongToken);
        wr.isLiquidation
            ? IVodkaV2(strategyAddresses.VodkaV2).fulfillLiquidation(key, totalLongToken, totalShortToken)
            : IVodkaV2(strategyAddresses.VodkaV2).fulfillClosePosition(key, totalLongToken, totalShortToken, estimatePositionProfit(key, longAmountFromGMX, usdcAmountFromGMX));
    }

    // @dev called after a withdrawal cancellation
    // @param key the key of the withdrawal
    // @param withdrawal the withdrawal that was cancelled
    function afterWithdrawalCancellation(
        bytes32 key,
        Withdrawal.Props memory withdrawal,
        EventUtils.EventLogData memory eventData
    ) external {
        require(IRoleStore(RoleStore).hasRole(msg.sender, Role.CONTROLLER), "Not proper role");
        // @note the below are not needed since GMX will refund the gm token and the long and short tokens will not be granted

        // IVodkaV2.WithdrawRecord memory wr = getWithdrawRecord(key);
        // IVodkaV2.GMXPoolAddresses memory gmp = IVodkaV2(strategyAddresses.VodkaV2).gmxPoolAddresses(wr.longToken);
        // OrderRefunded storage or = orderRefunded[key];
        IVodkaV2(strategyAddresses.VodkaV2).fulfillCancelWithdrawal(key);

        // console.log("afterWithdrawalCancellation");
        // console.log("marketTokenAmount returned: ", withdrawal.numbers.marketTokenAmount);
        // console.log("minLongTokenAmount: ", withdrawal.numbers.minLongTokenAmount);
        // console.log("minShortTokenAmount: ", withdrawal.numbers.minShortTokenAmount);
        // // payable(dr.user).transfer(eventData.uintItems.items[0].value);
        // // or.feesRefunded = eventData.uintItems.items[0].value;

        // or.gmTokensRefunded = wr.receivedMarketTokens;
        // or.cancelled = true;
        // or.depositOrWithdrawal = 1;
        // userRefunds[wr.user].push(key);
    }

    function estimatePositionProfit(bytes32 key, uint256 _returnedLongToken, uint256 _returnedShortToken) public view returns (uint256) {
        IVodkaV2.WithdrawRecord memory wr = getWithdrawRecord(key);
        IVodkaV2.PositionInfo memory pi = getPositionInfo(wr.user, wr.positionID);
        IVodkaV2.PositionDebt memory pb = getPositionDebt(wr.user, wr.positionID);

        // Calculate profit: 500 * 0.92 - 0.5 * $400 - $150 - $100 = $10
        // get the current price of long token
        uint256 longTokenPrice = getLatestData(wr.longToken, false);
        console.log("longTokenPrice", longTokenPrice);
        // convert _returnedLongToken to usdc based on the price of long token.
        // long token price is in pow of 18, so we need to convert it to pow of 6
        // _returnedLongToken is in pow of 18.
        uint256 longTokenValueInUSD = (_returnedLongToken * longTokenPrice) / (1e24 * 1e6);
        uint256 longTokenActualDebt = (pb.longDebtValue * longTokenPrice) / (1e24 * 1e6);

        console.log("longTokenValueInUSD", longTokenValueInUSD);
        // get the current price of short token
        uint256 shortTokenPrice = getLatestData(strategyAddresses.USDC, true);
        console.log("shortTokenPrice", shortTokenPrice);
        // convert _returnedShortToken to usdc based on the price of short token
        // _returnedShortToken is in pow of 6
        // short token price is in pow of 24, so we need to convert it to pow of 6
        // @todo fix
        uint256 shortTokenValue = ((_returnedShortToken * shortTokenPrice) / (1e6 * 1e18));
        console.log("shortTokenValue", shortTokenValue);
        // summation of long and short token value is the returned market token value in pow of 6
        uint256 marketTokenValue = longTokenValueInUSD + shortTokenValue;
        console.log("marketTokenValue", marketTokenValue);
        console.log("marketTokenValue", longTokenActualDebt);
        console.log("marketTokenValue", marketTokenValue - longTokenActualDebt - pb.shortDebtValue);
        console.log("========================================");
        uint256 sumAmount = longTokenActualDebt + pb.shortDebtValue + pi.deposit;
        uint256 profit = marketTokenValue > sumAmount ? marketTokenValue - sumAmount : 0;

        console.log("profit", profit);
        console.log("========================================");

        // calculate the profit
        // marketTokenValue: the value of the returned market in usdc which is (longTokenValueInUSD + shortTokenValue)
        // longTokenPrice: the price of long token in usdc which is in pow of 6
        // shortDebtValue: the amount of short token borrowed from lending pool in pow of 6
        // deposit: the amount of usdc deposited in pow of 6
        return profit;
    }

    function executeSwap(uint256 _amount, address _tokenIn, address _tokenOut, address _recipient) external returns (uint256) {
        require(msg.sender == strategyAddresses.VodkaV2, "Not VodkaV2");
        return _executeSwap(_amount, _tokenIn, _tokenOut, _recipient);
    }

    // withdraw tokens from the contract
    function withdrawTokens(address _token) external onlyOwner {
        IERC20Upgradeable(_token).safeTransfer(msg.sender, IERC20Upgradeable(_token).balanceOf(address(this)));
    }

    function _executeSwap(uint256 _amount, address _tokenIn, address _tokenOut, address _recipient) internal returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        console.log("_amount", _amount);
        IERC20Upgradeable(_tokenIn).approve(address(strategyAddresses.univ3Router), _amount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            fee: 3000,
            recipient: _recipient,
            deadline: block.timestamp,
            amountIn: _amount,
            //@todo have access to the oracle in gmx, can utilize that to get the price?
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = ISwapRouter(strategyAddresses.univ3Router).exactInputSingle(params);

        uint256 totalOut = amountOut;
        return totalOut;
    }

    receive() external payable {}
}

