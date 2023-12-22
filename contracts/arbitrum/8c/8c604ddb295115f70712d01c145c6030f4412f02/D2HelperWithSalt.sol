// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "./Math.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./IDeFiSystemReferenceV2.sol";
import "./ID2HelperBase.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./IWETH.sol";

contract D2HelperWithSalt is Ownable, ID2HelperBase {
    using Math for uint256;

    bool internal immutable hasAlternativeSwap;

    bool internal isInternal;
    bool internal isRunningArbitrage;
    bool internal swapSuccessful;

    enum Operation {
        ETH_TO_D2_INTERNAL_D2_TO_ETH_EXTERNAL,
        ETH_TO_D2_EXTERNAL_D2_TO_ETH_INTERNAL
    }

    Operation internal operation;

    IUniswapV2Router02 internal router;
    IUniswapV2Factory internal factory;
    IDeFiSystemReferenceV2 internal d2;
    IERC20 internal sdr;
    address internal immutable rsdTokenAddress;
    address internal immutable timeTokenAddress;

    address internal _pairD2Eth;
    address internal _pairD2Sdr;

    uint256 internal constant FACTOR = 10 ** 18;
    uint256 internal constant ARBITRAGE_RATE = 500;
    uint256 internal constant SWAP_FEE = 100;

    uint256[11] internal rangesWETH = [
        10_000_000 ether,
        1_000_000 ether,
        100_000 ether,
        10_000 ether,
        1_000 ether,
        100 ether,
        10 ether,
        1 ether,
        0.1 ether,
        0.01 ether,
        0.001 ether
    ];

    modifier fromD2() {
        require(msg.sender == address(d2), "D2 Helper: only D2 token contract can call this function");
        _;
    }

    modifier internalOnly() {
        require(isInternal, "D2 Helper: sorry buddy but you do not have access to this function");
        _;
    }

    modifier adjustInternalCondition() {
        isInternal = true;
        _;
        isInternal = false;
    }

    modifier runningArbitrage() {
        if (!isRunningArbitrage) {
            isRunningArbitrage = true;
            _;
            isRunningArbitrage = false;
        }
    }

    constructor(
        address _addressProvider,
        address _exchangeRouterAddress,
        address _d2TokenAddress,
        address _timeTokenAddress,
        address _rsdTokenAddress,
        address _sdrTokenAddress,
        bool _hasAlternativeSwap,
        address _owner
    ) {
        router = IUniswapV2Router02(_exchangeRouterAddress);
        factory = IUniswapV2Factory(router.factory());
        d2 = IDeFiSystemReferenceV2(payable(_d2TokenAddress));
        sdr = IERC20(_sdrTokenAddress);
        rsdTokenAddress = _rsdTokenAddress;
        timeTokenAddress = _timeTokenAddress;
        hasAlternativeSwap = _hasAlternativeSwap;
        transferOwnership(_owner);
        _createPairs();
    }

    function _calculateFee(uint256 amount) internal virtual returns (uint256) {
        return amount + amount.mulDiv(SWAP_FEE, 10_000);
    }

    function _startTraditionalSwap(address asset, uint256 amount) internal virtual returns (bool) {
        return false;
    }

    function _startAlternativeSwap(uint256 amountIn, uint256 amountOut) internal returns (bool) {
        address weth = router.WETH();
        swapSuccessful = false;
        IUniswapV2Pair pair = IUniswapV2Pair(_pairD2Eth);
        if (operation == Operation.ETH_TO_D2_EXTERNAL_D2_TO_ETH_INTERNAL) {
            uint256 amount0Out = address(d2) == pair.token0() ? amountOut : 0;
            uint256 amount1Out = address(d2) == pair.token1() ? amountOut : 0;
            try pair.swap(amount0Out, amount1Out, address(this), bytes(abi.encode(address(d2), amountOut))) {
                return swapSuccessful;
            } catch {
                return swapSuccessful;
            }
        } else {
            // ETH_TO_D2_INTERNAL_D2_TO_ETH_EXTERNAL
            uint256 amount0Out = weth == pair.token0() ? amountIn : 0;
            uint256 amount1Out = weth == pair.token1() ? amountIn : 0;
            try pair.swap(amount0Out, amount1Out, address(this), bytes(abi.encode(weth, amountIn))) {
                return swapSuccessful;
            } catch {
                return swapSuccessful;
            }
        }
    }

    receive() external payable { }

    fallback() external payable {
        require(msg.data.length == 0);
    }

    function _commonCall(address sender, bytes calldata data) internal {
        if (msg.sender == _pairD2Eth) {
            if (sender == address(this)) {
                // Operation.ETH_TO_D2_EXTERNAL_D2_TO_ETH_INTERNAL
                (address tokenToBorrow, uint256 amountToBorrow) = abi.decode(data, (address, uint256));
                if (tokenToBorrow == address(d2)) {
                    // 1. D2 -> ETH (Internal)
                    try d2.sellD2(amountToBorrow) {
                        address[] memory path = new address[](2);
                        path[0] = router.WETH();
                        path[1] = address(d2);
                        uint256[] memory amountRequired = router.getAmountsIn(amountToBorrow, path);
                        IWETH(path[0]).deposit{ value: amountRequired[0] }();
                        // 2. ETH -> D2 (External)
                        IERC20(path[0]).transfer(msg.sender, amountRequired[0]);
                        payable(address(d2)).call{ value: address(this).balance }("");
                        swapSuccessful = true;
                    } catch {
                        swapSuccessful = false;
                        return;
                    }
                } else {
                    // 1. ETH -> D2 (Internal)
                    address weth = router.WETH();
                    IWETH(weth).withdraw(amountToBorrow);
                    try d2.buyD2{ value: amountToBorrow }() {
                        address[] memory path = new address[](2);
                        path[0] = address(d2);
                        path[1] = weth;
                        uint256[] memory amountRequired = router.getAmountsIn(amountToBorrow, path);
                        // 2. D2 -> ETH (External)
                        IERC20(path[0]).transfer(msg.sender, amountRequired[0]);
                        try d2.sellD2(d2.balanceOf(address(this))) {
                            payable(address(d2)).call{ value: address(this).balance }("");
                            swapSuccessful = true;
                        } catch {
                            swapSuccessful = false;
                            return;
                        }
                    } catch {
                        swapSuccessful = false;
                        return;
                    }
                }
            }
        } else {
            swapSuccessful = false;
            return;
        }
    }

    function _createPairs() internal {
        _createPair(rsdTokenAddress, router.WETH());
        _createPair(rsdTokenAddress, address(sdr));
    }

    function _createPair(address asset01, address asset02) internal returns (address pair) {
        pair = factory.getPair(asset01, asset02);
        if (pair == address(0) && asset01 != address(0) && asset02 != address(0)) {
            try factory.createPair(asset01, asset02) returns (address p) {
                pair = p;
            } catch { }
        }
        return pair;
    }

    function _createPairsD2() internal {
        _pairD2Eth = _createPair(address(d2), router.WETH());
        _pairD2Sdr = _createPair(address(d2), address(sdr));
    }

    function _performOperation(address asset, uint256 amount) internal returns (bool) {
        if (operation == Operation.ETH_TO_D2_INTERNAL_D2_TO_ETH_EXTERNAL) {
            IWETH(asset).withdraw(amount); // assumming asset == weth
            try d2.buyD2{ value: amount }() {
                address[] memory path = new address[](2);
                path[0] = address(d2);
                path[1] = asset;
                uint256 d2Amount = d2.balanceOf(address(this));
                d2.approve(address(router), d2Amount);
                try router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    d2Amount,
                    0, // amount,
                    path,
                    address(this),
                    block.timestamp + 300
                ) {
                    return true;
                } catch {
                    return false;
                }
            } catch {
                return false;
            }
        } else {
            address[] memory path = new address[](2);
            path[0] = asset;
            path[1] = address(d2);
            IERC20(asset).approve(address(router), amount);
            try router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amount,
                0, //d2.queryD2AmountInternalLP(amount),
                path,
                address(this),
                block.timestamp + 300
            ) {
                uint256 d2Amount = d2.balanceOf(address(this));
                try d2.sellD2(d2Amount) {
                    IWETH(asset).deposit{ value: address(this).balance }();
                    return true;
                } catch {
                    return false;
                }
            } catch {
                return false;
            }
        }
    }

    /**
     * @dev Add liquidity for the D2/ETH pair LP in third party exchange (based on UniswapV2)
     *
     */
    function addLiquidityD2Native(uint256 d2Amount) external payable fromD2 returns (bool) {
        d2.approve(address(router), d2Amount);
        // add liquidity for the D2/ETH pair
        try router.addLiquidityETH{ value: msg.value }(
            address(d2),
            d2Amount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp + 300
        ) {
            return true;
        } catch {
            d2.returnNativeWithoutSharing{ value: msg.value }();
            return false;
        }
    }

    /**
     * @dev Add liquidity for the D2/SDR pair LP in third party exchange (based on UniswapV2)
     *
     */
    function addLiquidityD2Sdr() external fromD2 returns (bool) {
        uint256 d2TokenAmount = d2.balanceOf(address(this));
        uint256 sdrTokenAmount = sdr.balanceOf(address(this));
        // approve token transfer to cover all possible scenarios
        d2.approve(address(router), d2TokenAmount);
        sdr.approve(address(router), sdrTokenAmount);
        // add the liquidity for D2/SDR pair
        try router.addLiquidity(
            address(d2),
            address(sdr),
            d2TokenAmount,
            sdrTokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp + 300
        ) {
            return true;
        } catch {
            return false;
        }
    }

    function checkAndPerformArbitrage()
        external
        virtual
        runningArbitrage
        fromD2
        adjustInternalCondition
        returns (bool)
    {
        address weth = router.WETH();

        address pair = factory.getPair(address(d2), weth);
        uint256 balanceInternalNative = d2.poolBalance();
        uint256 balanceExternalNative = IERC20(weth).balanceOf(pair);
        uint256 balanceInternalD2 = d2.balanceOf(address(d2));
        uint256 balanceExternalD2 = d2.balanceOf(pair);

        if (balanceInternalNative == 0 || balanceExternalNative == 0) {
            return false;
        }

        uint256 rateInternal = balanceInternalD2.mulDiv(FACTOR, balanceInternalNative);
        uint256 rateExternal = balanceExternalD2.mulDiv(FACTOR, balanceExternalNative);

        if (rateExternal == 0 || rateInternal == 0) {
            return false;
        }

        bool shouldPerformArbitrage = (rateExternal > rateInternal)
            ? (rateExternal - rateInternal).mulDiv(10_000, rateExternal) >= ARBITRAGE_RATE
            : (rateInternal - rateExternal).mulDiv(10_000, rateInternal) >= ARBITRAGE_RATE;

        return (shouldPerformArbitrage ? _performArbitrage() : false);
    }

    function _performArbitrage() internal returns (bool success) {
        address weth = router.WETH();

        address[] memory assets_01 = new address[](2);
        assets_01[0] = weth;
        assets_01[1] = address(d2);
        address[] memory assets_02 = new address[](2);
        assets_02[0] = address(d2);
        assets_02[1] = weth;

        uint256[] memory amountOutExternal;
        uint256 amountOutInternal;

        address pair = factory.getPair(address(d2), weth);
        uint256 balanceInternalNative = d2.poolBalance();
        uint256 balanceExternalNative = IERC20(weth).balanceOf(pair);
        uint256 balanceInternalD2 = d2.balanceOf(address(d2));
        uint256 balanceExternalD2 = d2.balanceOf(pair);

        // getAmountsIn (amountOut, path) --> Given an amountOut value of path[1] token, it will tell us how many path[0] tokens we send
        // getAmountsOut(amountIn,  path) --> Given an amountIn  value of path[0] token, it will tell us how many path[1] tokens we receive
        for (uint256 i = 0; i < rangesWETH.length; i++) {
            amountOutExternal = router.getAmountsOut(rangesWETH[i], assets_01);
            amountOutInternal = d2.queryNativeAmount(amountOutExternal[1]);
            uint256 totalWithFee = _calculateFee(rangesWETH[i]);
            if (amountOutInternal <= totalWithFee) {
                amountOutInternal = d2.queryD2AmountOptimal(rangesWETH[i]);
                amountOutExternal = router.getAmountsOut(amountOutInternal, assets_02);
                if (amountOutExternal[1] > totalWithFee) {
                    // perform arbitrage here - Option #1 - Buy D2 LP Internal and Sell D2 LP External
                    if (balanceExternalNative >= amountOutExternal[1] && balanceInternalD2 >= amountOutInternal) {
                        operation = Operation.ETH_TO_D2_INTERNAL_D2_TO_ETH_EXTERNAL;
                        if (!hasAlternativeSwap) {
                            success = _startTraditionalSwap(weth, rangesWETH[i]);
                            if (!success) {
                                success = _startAlternativeSwap(rangesWETH[i], amountOutInternal);
                            }
                        } else {
                            success = _startAlternativeSwap(rangesWETH[i], amountOutInternal);
                        }
                        if (success) {
                            break;
                        }
                    }
                }
            } else {
                // perform arbitrage here - Option #2 - Buy D2 LP External and Sell D2 LP Internal
                if (balanceInternalNative >= amountOutInternal && balanceExternalD2 >= amountOutExternal[1]) {
                    operation = Operation.ETH_TO_D2_EXTERNAL_D2_TO_ETH_INTERNAL;
                    if (!hasAlternativeSwap) {
                        success = _startTraditionalSwap(weth, rangesWETH[i]);
                        if (!success) {
                            success = _startAlternativeSwap(rangesWETH[i], amountOutExternal[1]);
                        }
                    } else {
                        success = _startAlternativeSwap(rangesWETH[i], amountOutExternal[1]);
                    }
                    if (success) {
                        break;
                    }
                }
            }
        }
        return success;
    }

    function buyRsd() external payable fromD2 returns (bool) {
        // generate the pair path of ETH -> RSD on exchange router contract
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = rsdTokenAddress;

        try router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: msg.value }(
            0, // accept any amount of RSD
            path,
            address(this),
            block.timestamp + 300
        ) {
            return true;
        } catch {
            d2.returnNativeWithoutSharing{ value: msg.value }();
            return false;
        }
    }

    function buySdr() external fromD2 returns (bool) {
        IERC20 rsd = IERC20(rsdTokenAddress);
        uint256 rsdTokenAmount = rsd.balanceOf(address(this));
        // generate the pair path of RSD -> SDR on exchange router contract
        address[] memory path = new address[](2);
        path[0] = rsdTokenAddress;
        path[1] = address(sdr);

        rsd.approve(address(router), rsdTokenAmount);

        try router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            rsdTokenAmount,
            0, // accept any amount of SDR
            path,
            address(this),
            block.timestamp + 300
        ) {
            return true;
        } catch {
            return false;
        }
    }

    function kickBack() external payable fromD2 {
        payable(address(d2)).call{ value: msg.value }("");
    }

    function pancakeCall(address _sender, uint256 _amount0, uint256 _amount1, bytes calldata _data) external {
        _commonCall(_sender, _data);
    }

    function pairD2Eth() external view returns (address) {
        return _pairD2Eth;
    }

    function pairD2Sdr() external view returns (address) {
        return _pairD2Sdr;
    }

    function uniswapV2Call(address _sender, uint256 _amount0, uint256 _amount1, bytes calldata _data) external {
        _commonCall(_sender, _data);
    }

    function queryD2AmountFromSdr() external view fromD2 returns (uint256) {
        uint256 pairSdrBalance = sdr.balanceOf(factory.getPair(address(d2), address(sdr)));
        pairSdrBalance = (pairSdrBalance == 0) ? sdr.balanceOf(address(this)) : pairSdrBalance;
        return pairSdrBalance.mulDiv(queryD2SdrRate(), FACTOR);
    }

    function queryD2Rate() external view fromD2 returns (uint256) {
        address weth = router.WETH();
        uint256 ethBalance = IERC20(weth).balanceOf(_pairD2Eth);
        return (ethBalance == 0) ? FACTOR : d2.balanceOf(_pairD2Eth).mulDiv(FACTOR, ethBalance);
    }

    function queryD2SdrRate() public view fromD2 returns (uint256) {
        uint256 rate = d2.balanceOf(_pairD2Sdr).mulDiv(FACTOR, sdr.balanceOf(_pairD2Sdr) + 1);
        return (rate == 0 ? 1 : rate);
    }

    function queryPoolAddress() external view virtual returns (address) {
        return address(0);
    }

    function setD2(address d2Address) external virtual onlyOwner {
        d2 = IDeFiSystemReferenceV2(payable(d2Address));
        _createPairsD2();
    }

    function destroy() external virtual onlyOwner {
        selfdestruct(payable(msg.sender));
    }
}

