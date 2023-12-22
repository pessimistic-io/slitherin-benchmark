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

import "./console.sol";

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
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
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint amountOut);

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
    function exactInput(
        ExactInputParams calldata params
    ) external payable returns (uint amountOut);
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

    function fulfillOpenPosition(
        bytes32 key,
        uint256 _receivedTokens
    ) external returns (bool);

    function fulfillClosePosition(
        bytes32 key,
        uint256 _returnedLongAmount,
        uint256 _receivedUSDC,
        uint256 _longAmountValue
    ) external returns (bool);

    function fulfillLiquidation(
        bytes32 _key,
        uint256 _returnedLongAmount,
        uint256 _returnedUSDC
    ) external returns (bool);

    function depositRecord(
        bytes32 key
    ) external view returns (DepositRecord memory);

    function withdrawRecord(
        bytes32 key
    ) external view returns (WithdrawRecord memory);

    function gmxPoolAddresses(
        address longToken
    ) external view returns (GMXPoolAddresses memory);

    function positionDebt(
        address _user,
        uint256 _positionID
    ) external view returns (PositionDebt memory);
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
        uint256 residualOut;
        uint256 amountReturned;
        uint256 longAmountValue;
        uint256 residualConversion;
    }

    uint256[50] private __gaps;

    modifier zeroAddress(address addr) {
        require(addr != address(0), "Zero address");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _USDC,
        address _VodkaV2
    ) external initializer {
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
        //emit an event
    }

    function setChainlinkOracleForAsset(
        address _token,
        address _oracle
    ) external onlyOwner {
        require(_token != address(0), "Zero address");
        chainlinkOracle[_token] = _oracle;
    }

    function getLatestData(address _token, bool _inDecimal) public view returns (uint256) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) =  AggregatorV3Interface(chainlinkOracle[_token]).latestRoundData(); //in 1e8
        console.log("uint256(answer)", uint256(answer));

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

    function getDepositRecord(
        bytes32 key
    ) public view returns (IVodkaV2.DepositRecord memory) {
        return IVodkaV2(strategyAddresses.VodkaV2).depositRecord(key);
    }

    function getWithdrawRecord(
        bytes32 key
    ) public view returns (IVodkaV2.WithdrawRecord memory) {
        return IVodkaV2(strategyAddresses.VodkaV2).withdrawRecord(key);
    }

    function getPositionDebt(
        address _user,
        uint256 _positionID
    ) public view returns (IVodkaV2.PositionDebt memory) {
        return IVodkaV2(strategyAddresses.VodkaV2).positionDebt(_user, _positionID);
    }

    function getMarketTokenPrice(
        address longToken,
        bytes32 pnlFactorType,
        bool maximize
    ) public view returns (int256) {
        IVodkaV2.GMXPoolAddresses memory gmp = IVodkaV2(
            strategyAddresses.VodkaV2
        ).gmxPoolAddresses(longToken);
        Data memory data;
        Market.Props memory market = Market.Props({
            marketToken: gmp.marketToken,
            indexToken: gmp.indexToken,
            longToken: gmp.longToken,
            shortToken: gmp.shortToken
        });
        data.factorType = pnlFactorType;
        data.maximize = maximize;

        Price.Props memory indexTokenPrice = IOracle(strategyAddresses.oracle)
            .getPrimaryPrice(gmp.indexToken);

        Price.Props memory longTokenPrice = IOracle(strategyAddresses.oracle)
            .getPrimaryPrice(gmp.longToken);

        Price.Props memory shortTokenPrice = IOracle(strategyAddresses.oracle)
            .getPrimaryPrice(gmp.shortToken);

        (data.marketTokenPrice, ) = IReader(strategyAddresses.reader)
            .getMarketTokenPrice(
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

    function getEstimatedMarketTokenPrice(
        address longToken
    ) public view returns (int256) {
        IVodkaV2.GMXPoolAddresses memory gmp = IVodkaV2(
            strategyAddresses.VodkaV2
        ).gmxPoolAddresses(longToken);
        Market.Props memory market = Market.Props({
            marketToken: gmp.marketToken,
            indexToken: gmp.indexToken,
            longToken: gmp.longToken,
            shortToken: gmp.shortToken
        });

        Price.Props memory indexTokenPrice = Price.Props({
            max: uint256(getLatestData(gmp.indexToken,false)),
            min: uint256(getLatestData(gmp.indexToken,false))
        });

        uint256 index = uint256(getLatestData(gmp.indexToken,false));
        console.log("index", index);

        Price.Props memory longTokenPrice = Price.Props({
            //prettier ignore
            max: uint256(getLatestData(longToken,false)),
            min: uint256(getLatestData(longToken,false))
        });

        uint256 long = uint256(getLatestData(longToken,false));
        console.log("long", long);

        Price.Props memory shortTokenPrice = Price.Props({
            max: uint256(getLatestData(strategyAddresses.USDC,false)),
            min: uint256(getLatestData(strategyAddresses.USDC,false))
        });

        uint256 usdc = uint256(getLatestData(strategyAddresses.USDC,false));
        console.log("usdc", usdc);

        (int256 marketTokenPrice, ) = IReader(strategyAddresses.reader)
            .getMarketTokenPrice(
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
        console.log("marketTokenPrice", mp);

        return (marketTokenPrice);
    }

    function takeAll(address _inputSsset) public onlyOwner {
        uint256 balance = IERC20Upgradeable(_inputSsset).balanceOf(
            address(this)
        );
        IERC20Upgradeable(_inputSsset).transfer(msg.sender, balance);
    }

    function _setTempPayableAddress(address _tempPayableAddress) internal {
        tempPayableAddress = _tempPayableAddress;
    }

    /** -----GMX callback functions */
    function afterDepositExecution(
        bytes32 key,
        Deposit.Props memory deposit,
        EventUtils.EventLogData memory eventData
    ) external {
        require(
            msg.sender == strategyAddresses.depositHandler,
            "Not deposit handler"
        );
        IVodkaV2.DepositRecord memory dr = getDepositRecord(key);
        _setTempPayableAddress(dr.user);

        IVodkaV2(strategyAddresses.VodkaV2).fulfillOpenPosition(
            key,
            eventData.uintItems.items[0].value
        );
    }

    //NEED TO HANDLE REPAY TO THE RELEVANT VAULT
    function afterDepositCancellation(
        bytes32 key,
        Deposit.Props memory deposit,
        EventUtils.EventLogData memory eventData
    ) external {
        require(
            msg.sender == strategyAddresses.depositHandler,
            "Not deposit handler"
        );

        IVodkaV2.DepositRecord memory dr = getDepositRecord(key);
        OrderRefunded storage or = orderRefunded[key];

        // IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(
        //     dr.user,
        //     dr.depositedAmount
        // );
        // IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(
        //     strategyAddresses.WaterContract,
        //     dr.leverageAmount
        // );
        // IWater(strategyAddresses.WaterContract).repayDebt(
        //     dr.leverageAmount,
        //     dr.leverageAmount
        // );

        // payable(dr.user).transfer(eventData.uintItems.items[0].value);

        // or.feesRefunded = eventData.uintItems.items[0].value;
        // or.amountRefunded = dr.depositedAmount;
        // or.amountRepaid = dr.leverageAmount;
        // or.cancelled = true;
        // or.depositOrWithdrawal = 0;

        userRefunds[dr.user].push(key);
    }

    function afterWithdrawalExecution(
        bytes32 key,
        Withdrawal.Props memory withdrawal,
        EventUtils.EventLogData memory eventData
    ) external {
        require(
            msg.sender == strategyAddresses.withdrawalHandler,
            "Not withdrawal handler"
        );

        IVodkaV2.WithdrawRecord memory wr = getWithdrawRecord(key);
        IVodkaV2.PositionDebt memory pb = getPositionDebt(wr.user,wr.positionID);
        _setTempPayableAddress(wr.user);
        Data memory data;

        uint256 longDebtValue = pb.longDebtValue;
        uint256 shortDebtValue = pb.shortDebtValue;

        uint256 longAmountFromGMX = eventData.uintItems.items[0].value;
        uint256 usdcAmountFromGMX = eventData.uintItems.items[1].value;

        if (usdcAmountFromGMX < shortDebtValue) {
            data.residualOut = shortDebtValue - usdcAmountFromGMX;
            data.residualConversion = (data.residualOut * 1e12) * 1e18 / getLatestData(wr.longToken, true);
            data.amountReturned = _executeSwap(key, data.residualConversion, wr.longToken, strategyAddresses.USDC);
        } else if (longAmountFromGMX < longDebtValue) {
            data.residualOut = longDebtValue - longAmountFromGMX;
            data.residualConversion = (data.residualOut) * getLatestData(wr.longToken, true) / 1e18;
            data.amountReturned = _executeSwap(key,data.residualConversion, strategyAddresses.USDC, wr.longToken);
        }

        uint256 shortTokenBalance = IERC20Upgradeable(strategyAddresses.USDC).balanceOf(address(this));
        uint256 longTokenBalance = IERC20Upgradeable(wr.longToken).balanceOf(address(this));
        data.longAmountValue = getLatestData(wr.longToken, true) * longTokenBalance / 1e18;

        IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(strategyAddresses.VodkaV2,shortTokenBalance);
        IERC20Upgradeable(wr.longToken).safeTransfer(strategyAddresses.VodkaV2,longTokenBalance);

        wr.isLiquidation
            ? IVodkaV2(strategyAddresses.VodkaV2).fulfillLiquidation(
                key,
                longTokenBalance,
                shortTokenBalance
            )
            : IVodkaV2(strategyAddresses.VodkaV2).fulfillClosePosition(
                key,
                longTokenBalance,
                shortTokenBalance,
                data.longAmountValue
            );
    }

    function _executeSwap(
        bytes32 key,
        uint256 _amount,
        address _tokenIn,
        address _tokenOut) internal returns (uint256) {
        IVodkaV2.WithdrawRecord memory wr = getWithdrawRecord(key);

        IERC20Upgradeable(_tokenIn).approve(address(strategyAddresses.univ3Router),
        _amount
        );

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _amount,
                //@todo have access to the oracle in gmx, can utilize that to get the price?
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 amountOut = ISwapRouter(strategyAddresses.univ3Router)
            .exactInputSingle(params);

        uint256 totalOut = amountOut;
        return totalOut;
    }

    // @dev called after a withdrawal cancellation
    // @param key the key of the withdrawal
    // @param withdrawal the withdrawal that was cancelled
    function afterWithdrawalCancellation(
        bytes32 key,
        Withdrawal.Props memory withdrawal,
        EventUtils.EventLogData memory eventData
    ) external {
        require(
            msg.sender == strategyAddresses.withdrawalHandler,
            "Not withdrawal handler"
        );
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

