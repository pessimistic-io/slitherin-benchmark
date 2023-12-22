// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;
pragma abicoder v2;
import "./EnumerableSet.sol";
import "./IERC20.sol";
import "./IUniswapV3Pool.sol";
import "./TransferHelper.sol";
import "./INonfungiblePositionManager.sol";
import "./OracleLibrary.sol";
import "./AggregatorV3Interface.sol";
import "./Dev.sol";
import "./Fee.sol";
import "./ITradeEvent.sol";
import "./ISwapRouter02.sol";
import "./Common.sol";

// uniswap v3
abstract contract SwapV3 is Dev, Fee, Common {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet internal swapPairs;
    EnumerableSet.AddressSet internal swapRouterOrNfts; // route or nftman

    ISwapRouter02 internal immutable swapRouter;
    INonfungiblePositionManager internal immutable nftPositionManager;
    address internal uniswapPool;

    address public immutable WETH;
    address internal chainLinkEth; // Oracle
    address internal swapToken0; // main token，this contract
    address internal swapToken1; // other token
    uint256 internal ownTokenId;

    //  the pool fee to 0.3%.
    uint24 private constant poolFee = 3000;
    bool public addLpEnabled = false;
    bool public swapEnable = false;
    bool internal inSwap = false;

    event TradeTax(
        address indexed taxpayer,
        uint8 indexed source,
        uint256 amount
    );
    event UsdEvent(
        address indexed sender,
        uint256 amountIn,
        uint256 amountOut,
        uint256 usd,
        int24 tick1
    );

    modifier inSwapLock() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(
        ISwapRouter02 _swapRouter,
        INonfungiblePositionManager _nonfungiblePositionManager,
        address _chainLinkEth
    ) {
        swapRouter = _swapRouter;
        nftPositionManager = _nonfungiblePositionManager;
        chainLinkEth = _chainLinkEth;
        WETH = IPeripheryImmutableState(address(swapRouter)).WETH9();
        swapToken0 = address(this);
        swapToken1 = WETH;
        swapRouterOrNfts.add(address(nftPositionManager));
    }

    // lp pool add or dec
    function _isLpOpt(address from, address to) internal view returns (bool) {
        return isRouter(_msgSender()) || isRouter(from) || isRouter(to);
    }

    // Returns the latest ETH price in USD, need / 1e8
    function getETHPrice() public view returns (uint256) {
        (, int256 price, , , ) = AggregatorV3Interface(chainLinkEth)
            .latestRoundData();
        return uint256(price);
    }

    function _getAmountOutPrice(
        address sender,
        uint256 amountIn
    ) internal returns (uint256 usd) {
        if (uniswapPool == address(0)) {
            return 0;
        }
        (, int24 tick, , , , , ) = IUniswapV3Pool(uniswapPool).slot0();
        uint256 amountOut = OracleLibrary.getQuoteAtTick(
            tick,
            uint128(amountIn),
            swapToken0,
            swapToken1
        );
        usd = (getETHPrice() * amountOut) / 10 ** (18 + 8);
        emit UsdEvent(sender, amountIn, amountOut, usd, tick); // usd price
    }

    function isRouter(address _router) public view returns (bool) {
        return swapRouterOrNfts.contains(_router);
    }

    function addRouter(address _router) external onlyManger returns (bool) {
        return swapRouterOrNfts.add(_router);
    }

    function removeRouter(address _router) external onlyManger returns (bool) {
        return swapRouterOrNfts.remove(_router);
    }

    function isPair(address pool) public view returns (bool) {
        return swapPairs.contains(pool);
    }

    function getPair(uint256 index) public view returns (address) {
        return swapPairs.at(index);
    }

    function addPair(address pair) external onlyManger returns (bool) {
        return swapPairs.add(pair);
    }

    function removePair(address pair) external onlyManger returns (bool) {
        return swapPairs.remove(pair);
    }

    function setAddLpEnabled(bool _enabled) external onlyManger {
        addLpEnabled = _enabled;
    }

    function launch(address pool3000) external onlyManger {
        require(pool3000 != address(0), "pools zero");
        swapEnable = true;
        addLpEnabled = true;
        uniswapPool = pool3000;
        swapPairs.add(pool3000);
    }

    function _swapExactInput(
        address recipient,
        uint256 _amountIn
    ) internal returns (uint256 amountOut, bool success) {
        if (_amountIn == 0) {
            return (0, false);
        }
        (amountOut, success) = _swapExactInputRouter2(
            recipient,
            _amountIn,
            poolFee
        );
    }

    event SwapError(address sender, string msg);

    function _swapExactInputRouter2(
        address recipient,
        uint256 _amountIn,
        uint24 _poolFee
    ) internal returns (uint256 amountOut, bool success) {
        TransferHelper.safeApprove(swapToken0, address(swapRouter), _amountIn);
        IV3SwapRouter.ExactInputSingleParams memory swap_params = IV3SwapRouter
            .ExactInputSingleParams({
                tokenIn: swapToken0,
                tokenOut: swapToken1,
                fee: _poolFee,
                recipient: recipient,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        try swapRouter.exactInputSingle(swap_params) returns (uint256 out) {
            amountOut = out;
            success = true;
        } catch Error(string memory reason) {
            emit SwapError(_msgSender(), reason);
        }
    }

    function _doClaim() internal {
        if (
            jackpotAddress != address(0) &&
            !ITradeEvent(jackpotAddress).inProgress()
        ) try ITradeEvent(jackpotAddress).claimReward() {} catch {}
        if (
            luckyAddress != address(0) &&
            !ITradeEvent(luckyAddress).inProgress()
        ) try ITradeEvent(luckyAddress).claimReward() {} catch {}
    }

    function _transferFromSwap(
        address from,
        address to,
        uint256 amount,
        uint8 source
    ) internal inSwapLock returns (uint256 actualAmount) {
        actualAmount = amount;
        address user = source == 1 ? to : from;
        uint256 usd = _getAmountOutPrice(user, amount);
        if (source == 1) {
            // buy
            uint256 buyTax = _calcPercent(amount, _buyTotalFee());
            uint256 sellTax = _calcPercent(amount, _sellTotalFee());
            _collectTax(user, from, source, buyTax + sellTax);
            buyTotalTax += buyTax;
            sellTotalTax += sellTax;
            actualAmount = amount - buyTax - sellTax;
        }
        _doTradeEvent(source, user, usd);
    }

    function _doTradeEvent(uint8 source, address user, uint256 usd) internal {
        if (luckyAddress != address(0) && source == 1)
            try ITradeEvent(luckyAddress).trade(source, user, usd) {} catch {}

        if (jackpotAddress != address(0))
            try ITradeEvent(jackpotAddress).trade(source, user, usd) {} catch {}
    }

    function _collectTax(
        address taxpayer,
        address sender,
        uint8 source,
        uint256 tax
    ) internal {
        _innerTransfer(sender, address(this), tax);
        emit TradeTax(taxpayer, source, tax);
    }

    function _taxSwap() internal inSwapLock {
        _taxSwapSell();
        _taxSwapBuy();
    }

    function _taxSwapBuy() internal {
        if (
            buyTotalTax == 0 ||
            buyTotalTax > IERC20(address(this)).balanceOf(address(this))
        ) {
            return;
        }
        uint256 totalFee = _buyTotalFee();
        _doDevSwap(_calcPercent2(buyTotalTax, buyDevFee, totalFee));
        _doJackpotSwap(_calcPercent2(buyTotalTax, buyJackpotFee, totalFee));
        _addLp(_calcPercent2(buyTotalTax, buyLiquidityFee, totalFee));
        buyTotalTax = 0;
    }

    function _taxSwapSell() internal {
        if (
            sellTotalTax == 0 ||
            sellTotalTax > IERC20(address(this)).balanceOf(address(this))
        ) {
            return;
        }
        uint256 totalFee = _sellTotalFee();
        if (sellBlackFee > 0) {
            _innerTransfer(
                address(this),
                blackholdAddress,
                _calcPercent2(sellTotalTax, sellBlackFee, totalFee)
            );
        }
        _doDevSwap(_calcPercent2(sellTotalTax, sellDevFee, totalFee));
        _addLp(_calcPercent2(sellTotalTax, sellLiquidityFee, totalFee));
        _doJackpotSwap(_calcPercent2(sellTotalTax, sellJackpotFee, totalFee));
        _doLuckySwap(_calcPercent2(sellTotalTax, sellLuckyFee, totalFee));
        _doBouns(_calcPercent2(sellTotalTax, sellBonusFee, totalFee));

        sellTotalTax = 0;
    }

    function _doBouns(uint256 amount) internal {
        if (amount > 0 && jackpotAddress != address(0)) {
            _innerTransfer(address(this), jackpotAddress, amount);
        }
    }

    function _doDevSwap(uint256 amount) internal {
        if (amount > 0) _swapExactInput(devAddress, amount);
    }

    function _doLuckySwap(uint256 amount) internal {
        if (amount > 0 && luckyAddress != address(0))
            _swapExactInput(luckyAddress, amount);
    }

    function _doJackpotSwap(uint256 amount) internal {
        if (amount > 0 && jackpotAddress != address(0))
            _swapExactInput(jackpotAddress, amount);
    }

    function _addLp(uint256 liquidity) internal {
        uint256 half = liquidity / 2;
        if (half == 0) {
            return;
        }
        (uint256 wethAmount, bool success) = _swapExactInput(
            address(this),
            half
        );
        if (success) _doAddLp(half, wethAmount);
    }

    function _isTokenIdExist(
        uint256 tokenId
    ) internal view returns (bool exists) {
        try nftPositionManager.ownerOf(tokenId) returns (address _owner) {
            exists = address(this) == _owner;
        } catch {
            exists = false;
        }
    }

    function _doAddLp(uint256 amount0, uint256 amount1) internal {
        if (!addLpEnabled || amount0 == 0 || amount1 == 0) return;
        emit SwapAdd(amount0, amount1);
        if (ownTokenId == 0 || !_isTokenIdExist(ownTokenId)) {
            _mintNewPosition(swapToken0, swapToken1, amount0, amount1);
        } else {
            _increaseLp(ownTokenId, swapToken0, swapToken1, amount0, amount1);
        }
    }

    event SwapIncreaseError(address sender, string msg);
    event SwapAdd(uint256 amount0, uint256 amount1);

    function _increaseLp(
        uint256 tokenId,
        address token0,
        address token1,
        uint256 amountAdd0,
        uint256 amountAdd1
    ) private {
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
            (amountAdd0, amountAdd1) = (amountAdd1, amountAdd0);
        }
        IERC20(token0).approve(address(nftPositionManager), amountAdd0);
        IERC20(token1).approve(address(nftPositionManager), amountAdd1);
        try
            nftPositionManager.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: amountAdd0,
                    amount1Desired: amountAdd1,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 60
                })
            )
        {} catch Error(string memory reason) {
            emit SwapIncreaseError(_msgSender(), reason);
        }
    }

    event SwapMintError(address sender, string msg);

    function _mintNewPosition(
        address token0,
        address token1,
        uint256 amount0ToMint,
        uint256 amount1ToMint
    ) internal {
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
            (amount0ToMint, amount1ToMint) = (amount1ToMint, amount0ToMint);
        }
        IERC20(token0).approve(address(nftPositionManager), amount0ToMint);
        IERC20(token1).approve(address(nftPositionManager), amount1ToMint);
        try
            nftPositionManager.mint(
                INonfungiblePositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: poolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    amount0Desired: amount0ToMint,
                    amount1Desired: amount1ToMint,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp + 60
                })
            )
        returns (uint256 tokenId, uint128, uint256, uint256) {
            ownTokenId = tokenId;
            IERC721(address(nftPositionManager)).approve(owner(), ownTokenId);
        } catch Error(string memory reason) {
            emit SwapMintError(_msgSender(), reason);
        }
    }
}

