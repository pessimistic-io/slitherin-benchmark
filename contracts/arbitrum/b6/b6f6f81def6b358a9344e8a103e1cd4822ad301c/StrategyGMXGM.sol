// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IStrategyHelper} from "./IStrategyHelper.sol";
import {IExchangeRouter, IMarket, IReader, IPrice, IEventUtils, IDeposit, IWithdrawal} from "./IGMXGM.sol";
import {Strategy} from "./Strategy.sol";

interface IHandler {
    function depositVault() external view returns (address);
    function withdrawalVault() external view returns (address);
}

contract StrategyGMXGM is Strategy {
    IExchangeRouter public immutable exchangeRouter;
    IReader public immutable reader;
    address public depositHandler;
    address public withdrawalHandler;
    address public depositVault;
    address public withdrawalVault;
    address public immutable dataStore;
    address public immutable market;
    address public immutable tokenLong; // Volatile
    address public immutable tokenShort; // Stable
    uint256 public amountPendingDeposit;
    uint256 public amountPendingWithdraw;
    uint256 public reserveRatio = 1000; // 10%
    string public name;

    error NotGMX();
    error ActionPending();
    error WrongReserveRatio();

    constructor(
        address _strategyHelper,
        address _exchangeRouter,
        address _reader,
        address _depositHandler,
        address _withdrawalHandler,
        address _dataStore,
        address _market
    ) Strategy(_strategyHelper) {
        exchangeRouter = IExchangeRouter(_exchangeRouter);
        reader = IReader(_reader);
        depositHandler = _depositHandler;
        withdrawalHandler = _withdrawalHandler;
        depositVault = IHandler(_depositHandler).depositVault();
        withdrawalVault = IHandler(_withdrawalHandler).withdrawalVault();
        dataStore = _dataStore;
        market = _market;

        IMarket.Props memory marketInfo = reader.getMarket(_dataStore, market);
        tokenLong = marketInfo.longToken;
        tokenShort = marketInfo.shortToken;
        name = string(
            abi.encodePacked(
                "GMX GM ", IERC20(marketInfo.longToken).symbol(), "/", IERC20(marketInfo.shortToken).symbol()
            )
        );
    }

    function setReserveRatio(uint256 data) external auth {
        if (data > 10000) revert WrongReserveRatio();
        reserveRatio = data;
    }

    function setDepositHandler(address data) external auth {
        depositHandler = data;
        depositVault = IHandler(data).depositVault();
    }

    function setWithdrawalHandler(address data) external auth {
        withdrawalHandler = data;
        withdrawalVault = IHandler(data).withdrawalVault();
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        pull(IERC20(ast), msg.sender, amt);
        uint256 slp = getSlippage(dat);
        uint256 tot = totalShares;
        uint256 tma = rate(tot);

        IERC20(ast).approve(address(strategyHelper), amt);
        uint256 bal = strategyHelper.swap(ast, tokenShort, amt, slp, address(this));
        uint256 val = strategyHelper.value(tokenShort, bal);
        return tma == 0 ? val : val * tot / tma;
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        uint256 slp = getSlippage(dat);
        uint256 val = _rate(sha);
        uint256 amt = (val * (10 ** IERC20(tokenShort).decimals())) / strategyHelper.price(tokenShort);
        IERC20(tokenShort).approve(address(strategyHelper), amt);
        return strategyHelper.swap(tokenShort, ast, amt, slp, msg.sender);
    }

    function _earn() internal override {
        if (amountPendingDeposit != 0 || amountPendingWithdraw != 0) {
            revert ActionPending();
        }

        uint256 slp = slippage;
        uint256 bal = IERC20(tokenLong).balanceOf(address(this));
        if (bal > 0) {
            IERC20(tokenLong).approve(address(strategyHelper), bal);
            strategyHelper.swap(tokenLong, tokenShort, bal, slp, address(this));
        }

        bal = IERC20(tokenShort).balanceOf(address(this));
        uint256 have = strategyHelper.value(tokenShort, bal);
        uint256 need = _rate(totalShares) * reserveRatio / 10000;

        if (have > need) {
            uint256 amt = (have - need) * bal / have;
            uint256 haf = amt / 2;
            IERC20(tokenShort).approve(address(strategyHelper), haf);
            uint256 out = strategyHelper.swap(tokenShort, tokenLong, haf, slp, address(this));
            uint256 min = (have - need) * 1e18 / marketTokenPrice();
            amountPendingDeposit = min;
            min = min * (10000 - slp) / 10000;

            IExchangeRouter.CreateDepositParams memory params = IExchangeRouter.CreateDepositParams({
                receiver: address(this),
                callbackContract: address(this),
                uiFeeReceiver: address(0),
                market: market,
                initialLongToken: tokenLong,
                initialShortToken: tokenShort,
                longTokenSwapPath: new address[](0),
                shortTokenSwapPath: new address[](0),
                minMarketTokens: min,
                shouldUnwrapNativeToken: false,
                executionFee: msg.value,
                callbackGasLimit: 500000
            });

            IMarket.Props memory marketInfo = reader.getMarket(dataStore, market);
            bytes[] memory data = new bytes[](4);
            address router = exchangeRouter.router();
            address vault = depositVault;

            IERC20(marketInfo.longToken).approve(router, out);
            IERC20(marketInfo.shortToken).approve(router, amt - haf);

            data[0] = abi.encodeWithSelector(IExchangeRouter.sendWnt.selector, vault, params.executionFee);
            data[1] = abi.encodeWithSelector(IExchangeRouter.sendTokens.selector, marketInfo.longToken, vault, out);
            data[2] =
                abi.encodeWithSelector(IExchangeRouter.sendTokens.selector, marketInfo.shortToken, vault, amt - haf);
            data[3] = abi.encodeWithSelector(IExchangeRouter.createDeposit.selector, params);
            exchangeRouter.multicall{value: params.executionFee}(data);
        } else if (have < need) {
            uint256 amt = (need - have) * 1e18 / marketTokenPrice();

            IExchangeRouter.CreateWithdrawalParams memory params = IExchangeRouter.CreateWithdrawalParams({
                receiver: address(this),
                callbackContract: address(this),
                uiFeeReceiver: address(0),
                market: market,
                longTokenSwapPath: new address[](0),
                shortTokenSwapPath: new address[](0),
                minLongTokenAmount: 0,
                minShortTokenAmount: 0,
                shouldUnwrapNativeToken: false,
                executionFee: msg.value,
                callbackGasLimit: 500000
            });

            amountPendingWithdraw = amt;
            bytes[] memory data = new bytes[](3);
            IERC20(market).approve(exchangeRouter.router(), amt);
            data[0] = abi.encodeWithSelector(IExchangeRouter.sendWnt.selector, withdrawalVault, params.executionFee);
            data[1] = abi.encodeWithSelector(IExchangeRouter.sendTokens.selector, market, withdrawalVault, amt);
            data[2] = abi.encodeWithSelector(IExchangeRouter.createWithdrawal.selector, params);
            exchangeRouter.multicall{value: params.executionFee}(data);
        }
    }

    function _exit(address str) internal override {
        if (amountPendingDeposit != 0 || amountPendingWithdraw != 0) {
            revert ActionPending();
        }
        push(IERC20(market), str, IERC20(market).balanceOf(address(this)));
        push(IERC20(tokenLong), str, IERC20(tokenLong).balanceOf(address(this)));
        push(IERC20(tokenShort), str, IERC20(tokenShort).balanceOf(address(this)));
    }

    function _move(address old) internal override {}

    function _rate(uint256 sha) internal view override returns (uint256) {
        uint256 bal = IERC20(tokenLong).balanceOf(address(this));
        uint256 val = strategyHelper.value(tokenLong, bal);
        bal = IERC20(tokenShort).balanceOf(address(this));
        val += strategyHelper.value(tokenShort, bal);
        bal = IERC20(market).balanceOf(address(this)) + amountPendingDeposit + amountPendingWithdraw;
        val += (bal * marketTokenPrice() / 1e18);
        return sha * val / totalShares;
    }

    function marketTokenPrice() public view returns (uint256) {
        IReader rdr = reader;
        address dataStr = dataStore;
        IMarket.Props memory marketInfo = rdr.getMarket(dataStr, market);
        IStrategyHelper hlp = strategyHelper;

        uint256 price0 = hlp.price(marketInfo.indexToken) *
            (10 ** (30 - IERC20(marketInfo.indexToken).decimals())) / 1e18;
        uint256 price1 = hlp.price(marketInfo.longToken) *
            (10 ** (30 - IERC20(marketInfo.longToken).decimals())) / 1e18;
        uint256 price2 = hlp.price(marketInfo.shortToken) *
            (10 ** (30 - IERC20(marketInfo.shortToken).decimals())) / 1e18;

        IPrice.Props memory indexTokenPrice = IPrice.Props({min: price0, max: price0});
        IPrice.Props memory longTokenPrice = IPrice.Props({min: price1, max: price1});
        IPrice.Props memory shortTokenPrice = IPrice.Props({min: price2, max: price2});

        bytes32 pnlFactor = keccak256(abi.encode("MAX_PNL_FACTOR"));
        (int256 price,) = rdr.getMarketTokenPrice(
            dataStr, marketInfo, indexTokenPrice, longTokenPrice, shortTokenPrice, pnlFactor, false
        );

        // returned as 1e30, lets downscale to 1e18 used in here
        return uint256(price) / 1e12;
    }

    function afterDepositExecution(bytes32, IDeposit.Props memory, IEventUtils.EventLogData memory) external {
        if (msg.sender != depositHandler) revert NotGMX();
        amountPendingDeposit = 0;
    }

    function afterDepositCancellation(bytes32, IDeposit.Props memory, IEventUtils.EventLogData memory) external {
        if (msg.sender != depositHandler) revert NotGMX();
        amountPendingDeposit = 0;
    }

    function afterWithdrawalExecution(bytes32, IWithdrawal.Props memory, IEventUtils.EventLogData memory) external {
        if (msg.sender != withdrawalHandler) revert NotGMX();
        amountPendingWithdraw = 0;
    }

    function afterWithdrawalCancellation(bytes32, IWithdrawal.Props memory, IEventUtils.EventLogData memory) external {
        if (msg.sender != withdrawalHandler) revert NotGMX();
        amountPendingWithdraw = 0;
    }
}

