// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IRouter.sol";
import "./IFactory.sol";
import "./IPair.sol";
import "./IERC20.sol";
import "./ILpDepositor.sol";

import "./AccessControlEnumerableUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./Initializable.sol";

import "./ISwapRouter.sol";


// Swaps bribe/fee tokens to weth. Loosely based on Tarot optiswap. All swaps are made through ramses.
// it is now also a rudimentary zapper XD
contract bribeSwappoor_two is
    Initializable,
    AccessControlEnumerableUpgradeable
{
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    // Setting all these as constants because they are unlikely to change
    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    IFactory constant factory =
        IFactory(0xAAA20D08e59F6561f242b08513D36266C5A29415);
    address constant neadRamWeth = 0x1542D005D7b73c53a75D4Cd98a1a6bF3DC27842B;
    address constant ramWeth = 0x1E50482e9185D9DAC418768D14b2F2AC2b4DAF39;
    address constant ram = 0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418;
    address constant neadRam = 0x40301951Af3f80b8C1744ca77E55111dd3c1dba1;
    ILpDepositor constant depositor =
        ILpDepositor(0x1863736c768f232189F95428b5ed9A51B0eCcAe5);
    uint public targetRatio;
    uint public priceBasis;

    // token -> bridge token.
    mapping(address => address) tokenBridge;
    mapping(address => mapping(address => bool)) checkStable;
    // if token is tax token ffs...
    mapping(address => bool) isTax;
    // token -> externalDex
    mapping(address => bool) isExternalDex; // if no liquidity in ramses, use an external dex
    enum dexType {
        UNI_V2,
        UNI_V3
    }
    struct tokenDexData {
        address router;
        dexType _type;
        uint24 fee;
    }

    mapping(address => tokenDexData) tokenDex;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) external initializer {
        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SETTER_ROLE, admin);
    }

    // @notice checks if neadRam in or close to peg
    // @dev using the built in twap price feeds from baseV1Pair.
    function priceOutOfSync() public view returns (bool state) {
        // get current twap price of 100 neadRam in weth
        uint priceInWeth = IPair(neadRamWeth).current(neadRam, priceBasis);
        // get current twap of priceInWeth in ram
        uint priceInRam = IPair(ramWeth).current(weth, priceInWeth);
        state = priceInRam >= targetRatio ? false : true;
    }

    function setExternalDex(
        address token,
        address _router,
        dexType _type,
        bool isExternal,
        uint24 _fee
    ) external onlyRole(SETTER_ROLE) {
        isExternalDex[token] = isExternal;
        tokenDexData storage _data = tokenDex[token];
        _data.router = _router;
        _data._type = _type;
        if(_type == dexType.UNI_V3) _data.fee = _fee;
        IERC20(token).approve(_router, type(uint).max);
    }

    function setTargetRatio(uint ratio) external onlyRole(SETTER_ROLE) {
        targetRatio = ratio;
    }

    function setBasis(uint amount) external onlyRole(SETTER_ROLE) {
        priceBasis = amount;
    }

    function getBridgeToken(address _token) public view returns (address) {
        if (tokenBridge[_token] == address(0)) {
            return weth;
        }
        return tokenBridge[_token];
    }

    function addBridgeToken(
        address token,
        address bridge,
        bool stable
    ) external onlyRole(SETTER_ROLE) {
        require(token != weth, "Nope");
        tokenBridge[token] = bridge;
        checkStable[token][bridge] = stable;
    }

    function addBridgeTokenBulk(
        address[] calldata token,
        address[] calldata bridge,
        bool[] calldata stable
    ) external onlyRole(SETTER_ROLE) {
        for (uint i; i < token.length; ++i) {
            require(token[i] != weth, "Nope");
            tokenBridge[token[i]] = bridge[i];
            checkStable[token[i]][bridge[i]] = stable[i];
        }
    }

    function addTaxToken(address token) external onlyRole(SETTER_ROLE) {
        isTax[token] = true;
    }

    function removeBridge(
        address token,
        address bridge
    ) external onlyRole(SETTER_ROLE) {
        require(token != weth);
        delete tokenBridge[token];
        delete checkStable[token][bridge];
    }

    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "BaseV1Router: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "BaseV1Router: ZERO_ADDRESS");
    }

    function _pairFor(
        address tokenA,
        address tokenB,
        bool stable
    ) internal view returns (address pair) {
        pair = factory.getPair(tokenA, tokenB, stable);
    }

    function getAmountOut(
        uint amountA,
        bool stable,
        uint reserve0,
        uint reserve1,
        uint decimals0,
        uint decimals1
    ) internal pure returns (uint) {
        uint amountB;
        // gas savings, ramses pair contract would revert anyway if amountOut under/overflows
        unchecked {
            if (!stable) {
                amountB = (amountA * reserve1) / (reserve0 * 10000 + amountA);
            } else {
                amountA = amountA / 10000;
                uint xy = _k(reserve0, reserve1, decimals0, decimals1);
                amountA = (amountA * 10 ** 18) / decimals0;
                uint y = ((reserve1 * 10 ** 18) / decimals1) -
                    getY(
                        amountA + ((reserve0 * 10 ** 18) / decimals0),
                        xy,
                        reserve1
                    );
                amountB = (y * decimals1) / 10 ** 18;
            }
        }
        return amountB;
    }

    function getMetadata(
        address tokenA,
        address tokenB,
        address pair
    )
        internal
        view
        returns (uint decimalsA, uint decimalsB, uint reserveA, uint reserveB)
    {
        (address token0, ) = sortTokens(tokenA, tokenB);
        (
            uint decimals0,
            uint decimals1,
            uint reserve0,
            uint reserve1,
            ,
            ,

        ) = IPair(pair).metadata();
        (decimalsA, decimalsB, reserveA, reserveB) = tokenA == token0
            ? (decimals0, decimals1, reserve0, reserve1)
            : (decimals1, decimals0, reserve1, reserve0);
    }

    /**
     * @notice approve lpDepositor to spend neadRam/weth lp
     */
    function approveDepositor() external {
        IERC20(neadRamWeth).approve(address(depositor), type(uint).max);
    }

    /*
     * @notice zaps weth or neadRam to neadRam/weth lp only
     */
    function zapIn(bool isWeth, uint amountA, address to) external {
        address tokenA;
        address tokenB;
        (tokenA, tokenB) = isWeth ? (weth, neadRam) : (neadRam, weth);

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        (uint amountB, uint swapAmount) = _swapToLp(
            tokenA,
            tokenB,
            neadRamWeth,
            amountA
        );

        IERC20(tokenA).transfer(neadRamWeth, amountA - swapAmount);
        IERC20(tokenB).transfer(neadRamWeth, amountB);
        uint liquidity = IPair(neadRamWeth).mint(address(this));
        depositor.deposit(neadRamWeth, liquidity);
        IERC20(depositor.tokenForPool(neadRamWeth)).transfer(to, liquidity);
    }

    // @notice separate swap function specifically for zap() _swap is not compatible
    function _swapToLp(
        address tokenA,
        address tokenB,
        address pair,
        uint amount
    ) internal returns (uint, uint) {
        uint fee = factory.pairFee(pair) * 10000;
        (, , uint reserve0, uint reserve1) = getMetadata(tokenA, tokenB, pair);
        uint swapAmount = _calcSwap(reserve0, amount, fee);

        fee = 10000 - (fee / 10000);
        amount = swapAmount * fee;
        uint amountB = (amount * reserve1) / (reserve0 * 10000 + amount);

        IERC20(tokenA).transfer(pair, swapAmount);

        if (tokenA < tokenB) {
            IPair(pair).swap(0, amountB, address(this), "");
        } else {
            IPair(pair).swap(amountB, 0, address(this), "");
        }
        return (amountB, swapAmount);
    }

    function _swap(
        address tokenA,
        address tokenB,
        uint amountA,
        bool stable
    ) internal returns (uint) {
        address pair = _pairFor(tokenA, tokenB, stable);
        uint fee = factory.pairFee(pair);
        if (fee == 0) {
            fee = factory.getFee(stable);
        }
        fee *= 10000;
        (
            uint decimals0,
            uint decimals1,
            uint reserve0,
            uint reserve1
        ) = getMetadata(tokenA, tokenB, pair);

        unchecked {
            fee = 10000 - (fee / 10000);
        }

        amountA = IERC20(tokenA).balanceOf(address(this));
        IERC20(tokenA).transfer(pair, amountA);
        uint amountOut;
        amountOut = getAmountOut(
            amountA * fee,
            stable,
            reserve0,
            reserve1,
            decimals0,
            decimals1
        );
        // honestly ffs ppl shouldnt have to go through this, i hate external calls
        if (isTax[tokenA]) {
            uint pairBal = IERC20(tokenA).balanceOf(pair);
            amountOut = getAmountOut(
                (pairBal - reserve0) * fee,
                stable,
                reserve0,
                reserve1,
                decimals0,
                decimals1
            );
        }

        if (tokenA < tokenB) {
            IPair(pair).swap(0, amountOut, address(this), "");
        } else {
            IPair(pair).swap(amountOut, 0, address(this), "");
        }
        return (amountOut);
    }

    function swapOptimal(
        address tokenA,
        address tokenB,
        uint amount
    ) internal returns (uint) {
        address bridge;
        bool stable;
        if (tokenA == tokenB) {
            return amount;
        }
        bridge = getBridgeToken(tokenA);
        if (bridge == tokenB) {
            stable = checkStable[tokenA][bridge];
            return _swap(tokenA, tokenB, amount, stable);
        }
        address nextBridge = getBridgeToken(tokenB);
        if (tokenA == nextBridge) {
            stable = checkStable[tokenA][nextBridge];
            return _swap(tokenA, tokenB, amount, stable);
        }
        uint bridgeAmountOut;
        if (nextBridge != tokenA) {
            stable = checkStable[tokenA][bridge];
            bridgeAmountOut = _swap(tokenA, bridge, amount, stable);
        } else {
            bridgeAmountOut = amount;
        }
        if (bridge == nextBridge) {
            stable = checkStable[nextBridge][tokenB];
            return _swap(bridge, tokenB, bridgeAmountOut, stable);
        } else if (nextBridge == tokenB) {
            return swapOptimal(bridge, tokenB, bridgeAmountOut);
        } else {
            stable = checkStable[bridge][nextBridge];
            uint nextBridgeAmount = swapOptimal(
                bridge,
                nextBridge,
                bridgeAmountOut
            );
            stable = checkStable[nextBridge][tokenB];
            return _swap(nextBridge, tokenB, nextBridgeAmount, stable);
        }
    }

    function swapTokens(
        address tokenA,
        address tokenB,
        uint amount
    ) external returns (uint) {
        IERC20(tokenA).transferFrom(msg.sender, address(this), amount);
        if (isExternalDex[tokenA]) {
            address bridge = getBridgeToken(tokenA);
            if (bridge == tokenB) {
                return swapExternal(tokenA, tokenB, amount);
            } else {
                amount = swapExternal(tokenA, bridge, amount);
                tokenA = bridge;
            }
        }
        uint amountOut = swapOptimal(tokenA, tokenB, amount);
        uint bal = IERC20(tokenB).balanceOf(address(this));
        IERC20(tokenB).transfer(msg.sender, bal);
        amountOut = (amountOut * 900) / 1000;
        require(bal >= amountOut, "slippage");
        return bal;
    }

    function swapExternal(
        address tokenA,
        address tokenB,
        uint amount
    ) public returns (uint amountOut) {
        tokenDexData storage data = tokenDex[tokenA];
        if (data._type == dexType.UNI_V3) {
            amountOut = ISwapRouter(data.router).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenA,
                    tokenOut: tokenB,
                    fee: data.fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
    }

    function _calcSwap(
        uint reserve0,
        uint amountA,
        uint fee
    ) internal pure returns (uint) {
        uint x = 20000 - (fee / 10000);
        uint y = (4 * (10000 - (fee / 10000)) * 10000);
        uint z = 2 * (10000 - (fee / 10000));
        return
            (MathUpgradeable.sqrt(reserve0 * (x * x * reserve0 + amountA * y)) -
                reserve0 *
                x) / z;
    }

    // Doing all calculations locally instead of calling router.

    // k = xy(x^2 + y^2)
    function _k(
        uint x,
        uint y,
        uint decimals0,
        uint decimals1
    ) internal pure returns (uint) {
        unchecked {
            uint _x = (x * 10 ** 18) / decimals0;
            uint _y = (y * 10 ** 18) / decimals1;
            uint _a = (_x * _y) / 10 ** 18;
            uint _b = ((_x * _x) + (_y * _y)) / 10 ** 18;
            return (_a * _b) / 10 ** 18;
        }
    }

    function getY(uint x0, uint xy, uint y) internal pure returns (uint) {
        unchecked {
            for (uint i = 0; i < 255; ++i) {
                uint y_prev = y;
                uint k = _f(x0, y);
                if (k < xy) {
                    uint dy = ((xy - k) * 10 ** 18) / _d(x0, y);
                    y = y + dy;
                } else {
                    uint dy = ((k - xy) * 10 ** 18) / _d(x0, y);
                    y = y - dy;
                }
                if (y > y_prev) {
                    if (y - y_prev <= 1) {
                        return y;
                    }
                } else {
                    if (y_prev - y <= 1) {
                        return y;
                    }
                }
            }
            return y;
        }
    }

    function _f(uint x0, uint y) internal pure returns (uint) {
        unchecked {
            uint x3 = (x0 * x0 * x0) / 10 ** 36;
            uint y3 = (y * y * y) / 10 ** 36;
            uint a = (x0 * y3) / 10 ** 18;
            uint b = (x3 * y) / 10 ** 18;
            return a + b;
        }
    }

    function _d(uint x0, uint y) internal pure returns (uint) {
        unchecked {
            uint y2 = y * y;
            uint x3 = (x0 * x0 * x0) / 10 ** 36;
            uint a = 3 * x0 * y2;
            return (a / 10 ** 36) + x3;
        }
    }
}

