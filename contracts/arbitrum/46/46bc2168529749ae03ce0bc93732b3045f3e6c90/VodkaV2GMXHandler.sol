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

interface IRoleStore {
    function hasRole(address account, bytes32 roleKey) external view returns (bool);
}

library Role {
    /**
     * @dev The ROLE_ADMIN role.
     */
    bytes32 public constant ROLE_ADMIN = keccak256(abi.encode("ROLE_ADMIN"));

    /**
     * @dev The TIMELOCK_ADMIN role.
     */
    bytes32 public constant TIMELOCK_ADMIN = keccak256(abi.encode("TIMELOCK_ADMIN"));

    /**
     * @dev The TIMELOCK_MULTISIG role.
     */
    bytes32 public constant TIMELOCK_MULTISIG = keccak256(abi.encode("TIMELOCK_MULTISIG"));

    /**
     * @dev The CONFIG_KEEPER role.
     */
    bytes32 public constant CONFIG_KEEPER = keccak256(abi.encode("CONFIG_KEEPER"));

    /**
     * @dev The CONTROLLER role.
     */
    bytes32 public constant CONTROLLER = keccak256(abi.encode("CONTROLLER"));

    /**
     * @dev The ROUTER_PLUGIN role.
     */
    bytes32 public constant ROUTER_PLUGIN = keccak256(abi.encode("ROUTER_PLUGIN"));

    /**
     * @dev The MARKET_KEEPER role.
     */
    bytes32 public constant MARKET_KEEPER = keccak256(abi.encode("MARKET_KEEPER"));

    /**
     * @dev The FEE_KEEPER role.
     */
    bytes32 public constant FEE_KEEPER = keccak256(abi.encode("FEE_KEEPER"));

    /**
     * @dev The ORDER_KEEPER role.
     */
    bytes32 public constant ORDER_KEEPER = keccak256(abi.encode("ORDER_KEEPER"));

    /**
     * @dev The FROZEN_ORDER_KEEPER role.
     */
    bytes32 public constant FROZEN_ORDER_KEEPER = keccak256(abi.encode("FROZEN_ORDER_KEEPER"));

    /**
     * @dev The PRICING_KEEPER role.
     */
    bytes32 public constant PRICING_KEEPER = keccak256(abi.encode("PRICING_KEEPER"));
    /**
     * @dev The LIQUIDATION_KEEPER role.
     */
    bytes32 public constant LIQUIDATION_KEEPER = keccak256(abi.encode("LIQUIDATION_KEEPER"));
    /**
     * @dev The ADL_KEEPER role.
     */
    bytes32 public constant ADL_KEEPER = keccak256(abi.encode("ADL_KEEPER"));
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

    function repayDebt(uint256 leverage, uint256 debtValue) external;

    function getTotalDebt() external view returns (uint256);

    function updateTotalDebt(uint256 profit) external returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function balanceOfUSDC() external view returns (uint256);
}

interface IVodkaV2 {
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
    }

    struct GMXPoolAddresses {
        address longToken;
        address shortToken;
        address marketToken;
        address indexToken;
    }

    function getStrategyAddresses() external view returns (address[10] memory);

    function fulfillOpenPosition(bytes32 key, uint256 _receivedTokens) external returns (bool);
    function fulfillCancelDeposit(address longToken, uint256 amount) external;
    function fulfillCancelWithdrawal(bytes32 key) external;

    function fulfillClosePosition(bytes32 key, uint256 _receivedUSDC) external returns (bool);

    function fulfillLiquidation(bytes32 _key, uint256 _returnedUSDC) external returns (bool);

    function depositRecord(bytes32 key) external view returns (DepositRecord memory);

    function withdrawRecord(bytes32 key) external view returns (WithdrawRecord memory);

    function gmxPoolAddresses(address longToken) external view returns (GMXPoolAddresses memory);
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
        uint256 amountRepaid;
        uint256 gmTokensRefunded;
        uint256 depositOrWithdrawal; //0 deposit //1 withdrawal
        bool cancelled;
    }

    StrategyAddresses public strategyAddresses;

    mapping(bytes32 => OrderRefunded) public orderRefunded;
    mapping(address => bytes32[]) public userRefunds;
    mapping(address => address) public chainlinkOracle;

    address public tempPayableAddress;

    struct Data {
        int256 marketTokenPrice;
        bytes32 factorType;
        bool maximize;
    }

    uint256[50] private __gaps;
    address public WETH;
    uint24 public univ3Fee;
    address public RoleStore;
    uint256 private constant GRACE_PERIOD_TIME = 3600; // 1 hour
    address public arbitrumSequencer;
    address feeReceiver;

    event StrategyParamsSet(
        address univ3Router,
        address dataStore,
        address oracle,
        address reader,
        address depositHandler,
        address withdrawalHandler
    );
    event ChainlinkOracleSet(address token, address oracle);
    event RepayDepositFailure(address user, string reason, bytes data);
    event FeeReceiverSet(address receiver);

    modifier zeroAddress(address addr) {
        require(addr != address(0), "Zero address");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _USDC, address _WaterContract, address _VodkaV2) external initializer {
        strategyAddresses.VodkaV2 = _VodkaV2;
        strategyAddresses.WaterContract = _WaterContract;
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

    function setFeeReceiver(address _newFeeReceiver) external onlyOwner {
        require(_newFeeReceiver != address(0), "Zero address");
        feeReceiver = _newFeeReceiver;
        emit FeeReceiverSet(_newFeeReceiver);
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

    function setArbitrumSequencer(address _arbitrumSequencer) external onlyOwner {
        arbitrumSequencer = _arbitrumSequencer;
    }

    function setWETH(address _WETH) external onlyOwner {
        WETH = _WETH;
    }

    function setUniv3Fee(uint24 _univ3Fee) external onlyOwner {
        require(_univ3Fee <= 5000, "Fee too high");
        univ3Fee = _univ3Fee;
    }

    function setRoleStore(address _roleStore) external onlyOwner {
        RoleStore = _roleStore;
    }

    function setChainlinkOracleForAsset(address _token, address _oracle) external onlyOwner {
        require(_token != address(0), "Zero address");
        chainlinkOracle[_token] = _oracle;
        emit ChainlinkOracleSet(_token, _oracle);
    }

    function getLatestData(address _token) public view returns (uint256) {
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
        require(isSequencerUp, "Sequencer is down");

        // Make sure the grace period has passed after the
        // sequencer is back up.
        uint256 timeSinceUp = block.timestamp - sqStartedAt;
        require(timeSinceUp > GRACE_PERIOD_TIME, "Grace period not over");

        (, /* uint80 roundID */ int answer /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/, , , ) = AggregatorV3Interface(
            chainlinkOracle[_token]
        ).latestRoundData(); //in 1e8

        uint256 decimalPrice;
        if (_token == strategyAddresses.USDC) {
            decimalPrice = uint256(answer) * 1e10 * 1e6; //gmx v2 price format
        } else {
            decimalPrice = (uint256(answer) * 1e10) / 1e6;
        }

        return decimalPrice;
    }

    function getDepositRecord(bytes32 key) public view returns (IVodkaV2.DepositRecord memory) {
        return IVodkaV2(strategyAddresses.VodkaV2).depositRecord(key);
    }

    function getWithdrawRecord(bytes32 key) public view returns (IVodkaV2.WithdrawRecord memory) {
        return IVodkaV2(strategyAddresses.VodkaV2).withdrawRecord(key);
    }

    function getEstimatedMarketTokenPrice(address longToken) public view returns (int256, uint256, uint256, uint256) {
        IVodkaV2.GMXPoolAddresses memory gmp = IVodkaV2(strategyAddresses.VodkaV2).gmxPoolAddresses(longToken);
        Market.Props memory market = Market.Props({
            marketToken: gmp.marketToken,
            indexToken: gmp.indexToken,
            longToken: gmp.longToken,
            shortToken: gmp.shortToken
        });

        Price.Props memory indexTokenPrice = Price.Props({
            max: uint256(getLatestData(gmp.indexToken)),
            min: uint256(getLatestData(gmp.indexToken))
        });

        uint256 index = uint256(getLatestData(gmp.indexToken));

        Price.Props memory longTokenPrice = Price.Props({
            //prettier ignore
            max: uint256(getLatestData(longToken)),
            min: uint256(getLatestData(longToken))
        });

        uint256 long = uint256(getLatestData(longToken));

        Price.Props memory shortTokenPrice = Price.Props({
            max: uint256(getLatestData(strategyAddresses.USDC)),
            min: uint256(getLatestData(strategyAddresses.USDC))
        });

        uint256 usdc = uint256(getLatestData(strategyAddresses.USDC));

        (int256 marketTokenPrice, ) = IReader(strategyAddresses.reader).getMarketTokenPrice(
            strategyAddresses.dataStore,
            market,
            indexTokenPrice,
            longTokenPrice,
            shortTokenPrice,
            keccak256("MAX_PNL_FACTOR_FOR_WITHDRAWALS"),
            false
        );

        marketTokenPrice = marketTokenPrice / 1e12;
        uint256 mp = uint256(marketTokenPrice);

        return (marketTokenPrice, indexTokenPrice.max, longTokenPrice.max, shortTokenPrice.max);
    }

    // in case funds get stucked after a bad cancellation management/edge case
    function takeAll(address _inputAsset) public onlyOwner {
        uint256 balance = IERC20Upgradeable(_inputAsset).balanceOf(address(this));
        IERC20Upgradeable(_inputAsset).transfer(msg.sender, balance);
    }

    /** -----GMX callback functions */
    function afterDepositExecution(bytes32 key, Deposit.Props memory deposit, EventUtils.EventLogData memory eventData) external {
        require(deposit.addresses.account == strategyAddresses.VodkaV2, "Account isnt VodkaV2");
        require(IRoleStore(RoleStore).hasRole(msg.sender, Role.CONTROLLER), "Not proper role");
        IVodkaV2.DepositRecord memory dr = getDepositRecord(key);
        tempPayableAddress = dr.user;

        IVodkaV2(strategyAddresses.VodkaV2).fulfillOpenPosition(key, eventData.uintItems.items[0].value);
    }

    // @dev called after a deposit cancellation
    // @param key the key of the deposit
    // @param deposit the deposit that was cancelled
    function afterDepositCancellation(bytes32 key, Deposit.Props memory deposit, EventUtils.EventLogData memory eventData) external {
        if (msg.sender != owner()) {
            require(deposit.addresses.account == strategyAddresses.VodkaV2, "Account isnt VodkaV2");
            require(IRoleStore(RoleStore).hasRole(msg.sender, Role.CONTROLLER), "Not proper role");
        }

        IVodkaV2.DepositRecord memory dr = getDepositRecord(key);
        IVodkaV2.GMXPoolAddresses memory gmp = IVodkaV2(strategyAddresses.VodkaV2).gmxPoolAddresses(dr.longToken);
        OrderRefunded storage or = orderRefunded[key];

        IVodkaV2(strategyAddresses.VodkaV2).fulfillCancelDeposit(gmp.longToken, dr.depositedAmount + dr.leverageAmount);

        try IERC20Upgradeable(strategyAddresses.USDC).transfer(dr.user, dr.depositedAmount) returns (bool success) {
            require(success, "USDC transfer failed");
        } catch Error(string memory errorMessage) {
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(owner(), dr.depositedAmount);
            emit RepayDepositFailure(dr.user, errorMessage, "");
        }

        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.WaterContract, dr.leverageAmount);
        IWater(strategyAddresses.WaterContract).repayDebt(dr.leverageAmount, dr.leverageAmount);

        // bool success = payable(dr.user).send(eventData.uintItems.items[0].value);
        // there is little chance of this happening but if it does, cause
        // The thing is the gas estimate is done by GMX beforehand, during the call to this functions, 
        // so it can't fail Because GMX compute how much gas will be used before it's accepted on their end and 
        // we always ensure the fee is paid upfront. Their callback requires us to pass in the gas required, 
        // That's how the fee is computed, So we always ensure its more than necessary so that their callback executes on our end.
        // if (!success) {
        //     payable(feeReceiver).send(eventData.uintItems.items[0].value);
        // }

        or.feesRefunded = deposit.numbers.executionFee;
        or.amountRefunded = dr.depositedAmount;
        or.amountRepaid = dr.leverageAmount;
        or.cancelled = true;
        or.depositOrWithdrawal = 0;

        userRefunds[dr.user].push(key);
    }

    function afterWithdrawalExecution(bytes32 key, Withdrawal.Props memory withdrawal, EventUtils.EventLogData memory eventData) external {
        require(withdrawal.addresses.account == strategyAddresses.VodkaV2, "Account isnt VodkaV2");
        require(IRoleStore(RoleStore).hasRole(msg.sender, Role.CONTROLLER), "Not proper role");

        uint256 longAmountFromGMX = eventData.uintItems.items[0].value;
        uint256 usdcAmountFromGMX = eventData.uintItems.items[1].value;

        IVodkaV2.WithdrawRecord memory wr = getWithdrawRecord(key);
        IERC20Upgradeable(wr.longToken).approve(address(strategyAddresses.univ3Router), longAmountFromGMX);

        uint256 amountOut;
        if (wr.longToken != WETH) {
            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: abi.encodePacked(wr.longToken, univ3Fee, WETH, univ3Fee, strategyAddresses.USDC),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: longAmountFromGMX,
                amountOutMinimum: 0
            });

            amountOut = ISwapRouter(strategyAddresses.univ3Router).exactInput(params);
        } else {
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: wr.longToken,
                tokenOut: strategyAddresses.USDC,
                fee: univ3Fee,
                recipient: address(this),
                deadline: block.timestamp + 5 minutes,
                amountIn: longAmountFromGMX,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            amountOut = ISwapRouter(strategyAddresses.univ3Router).exactInputSingle(params);
        }

        uint256 totalUSDC = usdcAmountFromGMX + amountOut;
        IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(strategyAddresses.VodkaV2, totalUSDC);
        tempPayableAddress = wr.user;

        wr.isLiquidation
            ? IVodkaV2(strategyAddresses.VodkaV2).fulfillLiquidation(key, totalUSDC)
            : IVodkaV2(strategyAddresses.VodkaV2).fulfillClosePosition(key, totalUSDC);
    }

    // @dev called after a withdrawal cancellation
    // @param key the key of the withdrawal
    // @param withdrawal the withdrawal that was cancelled
    function afterWithdrawalCancellation(
        bytes32 key,
        Withdrawal.Props memory withdrawal,
        EventUtils.EventLogData memory eventData
    ) external {
        require(withdrawal.addresses.account == strategyAddresses.VodkaV2, "Account isnt VodkaV2");
        require(IRoleStore(RoleStore).hasRole(msg.sender, Role.CONTROLLER), "Not proper role");
        IVodkaV2.WithdrawRecord memory wr = getWithdrawRecord(key);
        OrderRefunded storage or = orderRefunded[key];

        // GMX directly sends the fees remnant to the user
        IVodkaV2(strategyAddresses.VodkaV2).fulfillCancelWithdrawal(key);

        or.feesRefunded = withdrawal.numbers.executionFee;
        or.gmTokensRefunded = wr.gmTokenWithdrawnAmount;
        or.cancelled = true;
        or.depositOrWithdrawal = 1;

        userRefunds[wr.user].push(key);
    }

    receive() external payable {}
}

