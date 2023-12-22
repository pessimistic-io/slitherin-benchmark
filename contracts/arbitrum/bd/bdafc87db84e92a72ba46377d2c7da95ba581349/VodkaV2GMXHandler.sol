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
import "./IWater.sol";
import "./ISwapRouter.sol";

import "./console.sol";

interface IVodkaV2 {
    struct DepositRecord {
        address user;
        uint256 depositedAmount;
        uint256 leverageAmount;
        uint256 receivedMarketTokens;
        uint256 feesPaid;
        bool success;
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
    }

    function getStrategyAddresses() external view returns (address[10] memory);

    function fulfillOpenPosition(bytes32 key, uint256 _receivedTokens) external returns (bool);

    function fulfillClosePosition(bytes32 key, uint256 _receivedUSDC) external returns (bool);

    function depositRecord(bytes32 key) external view returns (DepositRecord memory);

    function withdrawRecord(bytes32 key) external view returns (WithdrawRecord memory);
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
        address WETH;
        address WaterContract;
        address VodkaV2;
        address univ3Router;
        address dataStore;
        address oracle;
        address indexToken;
        address reader;
        address gmToken;
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

    uint256[50] private __gaps;
    bool public passed;
    int256 public lastPrice;
    int256 public lastPrice2;

    modifier zeroAddress(address addr) {
        require(addr != address(0), "Zero address");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _USDC, address _WETH, address _WaterContract, address _VodkaV2) external initializer {
        strategyAddresses.VodkaV2 = _VodkaV2;
        strategyAddresses.WaterContract = _WaterContract;
        strategyAddresses.USDC = _USDC;
        strategyAddresses.WETH = _WETH;

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

    //function to set all variables setStrategyParams
    function setStrategyParams(
        address _univ3Router,
        address _dataStore,
        address _oracle,
        address _indexToken,
        address _reader,
        address _gmToken,
        address _depositHandler,
        address _withdrawalHandler
    ) external onlyOwner {
        strategyAddresses.univ3Router = _univ3Router;
        strategyAddresses.dataStore = _dataStore;
        strategyAddresses.oracle = _oracle;
        strategyAddresses.indexToken = _indexToken;
        strategyAddresses.reader = _reader;
        strategyAddresses.gmToken = _gmToken;
        strategyAddresses.depositHandler = _depositHandler;
        strategyAddresses.withdrawalHandler = _withdrawalHandler;
        //emit an event
    }

    function getDepositRecord(bytes32 key) public view returns (IVodkaV2.DepositRecord memory) {
        return IVodkaV2(strategyAddresses.VodkaV2).depositRecord(key);
    }

    function getWithdrawRecord(bytes32 key) public view returns (IVodkaV2.WithdrawRecord memory) {
        return IVodkaV2(strategyAddresses.VodkaV2).withdrawRecord(key);
    }

    function takeAll(address _inputSsset, uint256 _amount) public onlyOwner {
        IERC20Upgradeable(_inputSsset).transfer(msg.sender, _amount);
    }

    /** -----GMX callback functions */
    function afterDepositExecution(bytes32 key, Deposit.Props memory deposit, EventUtils.EventLogData memory eventData) external {
        require(msg.sender == strategyAddresses.depositHandler, "Not deposit handler");
        IVodkaV2(strategyAddresses.VodkaV2).fulfillOpenPosition(key, eventData.uintItems.items[0].value);
    }

    function getMarketTokenPrice() public view returns (int256) {
        Market.Props memory market = Market.Props({
            marketToken: strategyAddresses.gmToken,
            indexToken: strategyAddresses.indexToken,
            longToken: strategyAddresses.WETH,
            shortToken: strategyAddresses.USDC
        });

        Price.Props memory indexTokenPrice = IOracle(strategyAddresses.oracle).getPrimaryPrice(strategyAddresses.indexToken);

        Price.Props memory longTokenPrice = IOracle(strategyAddresses.oracle).getPrimaryPrice(strategyAddresses.WETH);

        Price.Props memory shortTokenPrice = IOracle(strategyAddresses.oracle).getPrimaryPrice(strategyAddresses.USDC);

        (int256 marketTokenPrice, ) = IReader(strategyAddresses.reader).getMarketTokenPrice(
            strategyAddresses.dataStore,
            market,
            indexTokenPrice,
            longTokenPrice,
            shortTokenPrice,
            keccak256("MAX_PNL_FACTOR_FOR_DEPOSITS"),
            true
        );

        marketTokenPrice = marketTokenPrice / 1e12;

        return (marketTokenPrice);
    }

    // @dev called after a deposit cancellation
    // @param key the key of the deposit
    // @param deposit the deposit that was cancelled
    function afterDepositCancellation(bytes32 key, Deposit.Props memory deposit, EventUtils.EventLogData memory eventData) external {
        require(msg.sender == strategyAddresses.depositHandler, "Not deposit handler");

        IVodkaV2.DepositRecord memory dr = getDepositRecord(key);
        OrderRefunded storage or = orderRefunded[key];

        IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(dr.user, dr.depositedAmount);
        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.WaterContract, dr.leverageAmount);
        IWater(strategyAddresses.WaterContract).repayDebt(dr.leverageAmount, dr.leverageAmount);

        payable(dr.user).transfer(eventData.uintItems.items[0].value);

        or.feesRefunded = eventData.uintItems.items[0].value;
        or.amountRefunded = dr.depositedAmount;
        or.amountRepaid = dr.leverageAmount;
        or.cancelled = true;
        or.depositOrWithdrawal = 0;

        userRefunds[dr.user].push(key);
    }

    function afterWithdrawalExecution(bytes32 key, Withdrawal.Props memory withdrawal, EventUtils.EventLogData memory eventData) external {
        require(msg.sender == strategyAddresses.withdrawalHandler, "Not withdrawal handler");

        uint256 ethAmountFromGMX = eventData.uintItems.items[0].value;
        uint256 usdcAmountFromGMX = eventData.uintItems.items[1].value;

        IERC20Upgradeable(strategyAddresses.WETH).approve(address(strategyAddresses.univ3Router), ethAmountFromGMX);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: strategyAddresses.WETH,
            tokenOut: strategyAddresses.USDC,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: ethAmountFromGMX,
            //@todo have access to the oracle in gmx, can utilize that to get the price?
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = ISwapRouter(strategyAddresses.univ3Router).exactInputSingle(params);

        uint256 totalUSDC = usdcAmountFromGMX + amountOut;
        IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(strategyAddresses.VodkaV2, totalUSDC);

        IVodkaV2(strategyAddresses.VodkaV2).fulfillClosePosition(key, totalUSDC);
    }

    // @dev called after a withdrawal cancellation
    // @param key the key of the withdrawal
    // @param withdrawal the withdrawal that was cancelled
    function afterWithdrawalCancellation(
        bytes32 key,
        Withdrawal.Props memory withdrawal,
        EventUtils.EventLogData memory eventData
    ) external {
        require(msg.sender == strategyAddresses.withdrawalHandler, "Not withdrawal handler");
        IVodkaV2.WithdrawRecord memory wr = getWithdrawRecord(key);
        OrderRefunded storage or = orderRefunded[key];

        payable(wr.user).transfer(eventData.uintItems.items[0].value);

        or.feesRefunded = eventData.uintItems.items[0].value;
        or.gmTokensRefunded = wr.gmTokenWithdrawnAmount;
        or.cancelled = true;
        or.depositOrWithdrawal = 1;

        userRefunds[wr.user].push(key);
    }

    receive() external payable {}
}

