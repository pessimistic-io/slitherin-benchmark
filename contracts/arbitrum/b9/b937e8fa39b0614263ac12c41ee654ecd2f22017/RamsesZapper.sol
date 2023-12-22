// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IPair.sol";
import "./IPairFactory.sol";
import "./IWETH.sol";
import "./MathUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./Initializable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./MulticallUpgradeable.sol";

contract RamsesZapper is
    Initializable,
    MulticallUpgradeable,
    AccessControlEnumerableUpgradeable
{
    struct route {
        address from;
        address to;
        bool stable;
    }

    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    uint public constant MINIMUM_LIQUIDITY = 10 ** 3;

    IPairFactory public factory;
    IWETH public weth;

    mapping(address => bool) public isTax; // If token is fee on transfer

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        IPairFactory _factory,
        IWETH _weth
    ) external initializer {
        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SETTER_ROLE, admin);

        factory = _factory;
        weth = _weth;
    }

    function addTaxToken(address token) external onlyRole(SETTER_ROLE) {
        isTax[token] = true;
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

    function pairFor(
        address tokenA,
        address tokenB,
        bool stable
    ) public view returns (address pair) {
        pair = factory.getPair(tokenA, tokenB, stable);
    }

    // @notice given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quoteLiquidity(
        uint amountA,
        uint reserveA,
        uint reserveB
    ) internal pure returns (uint amountB) {
        require(amountA > 0, "BaseV1Router: INSUFFICIENT_AMOUNT");
        require(
            reserveA > 0 && reserveB > 0,
            "BaseV1Router: INSUFFICIENT_LIQUIDITY"
        );
        amountB = (amountA * reserveB) / reserveA;
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

    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired
    ) public view returns (uint amountA, uint amountB, uint liquidity) {
        address _pair = pairFor(tokenA, tokenB, stable);
        (uint reserveA, uint reserveB) = (0, 0);
        uint _totalSupply = 0;
        if (_pair != address(0)) {
            _totalSupply = IERC20Upgradeable(_pair).totalSupply();
            (, , reserveA, reserveB) = getMetadata(tokenA, tokenB, _pair);
        }
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
            liquidity =
                MathUpgradeable.sqrt(amountA * amountB) -
                MINIMUM_LIQUIDITY;
        } else {
            uint amountBOptimal = quoteLiquidity(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
                liquidity = MathUpgradeable.min(
                    (amountA * _totalSupply) / reserveA,
                    (amountB * _totalSupply) / reserveB
                );
            } else {
                uint amountAOptimal = quoteLiquidity(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                (amountA, amountB) = (amountAOptimal, amountBDesired);
                liquidity = MathUpgradeable.min(
                    (amountA * _totalSupply) / reserveA,
                    (amountB * _totalSupply) / reserveB
                );
            }
        }
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal returns (uint amountA, uint amountB) {
        require(amountADesired >= amountAMin);
        require(amountBDesired >= amountBMin);
        address _pair = factory.getPair(tokenA, tokenB, stable);
        if (_pair == address(0)) {
            _pair = factory.createPair(tokenA, tokenB, stable);
        }
        (, , uint reserveA, uint reserveB) = getMetadata(tokenA, tokenB, _pair);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = quoteLiquidity(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                require(
                    amountBOptimal >= amountBMin,
                    "BaseV1Router: INSUFFICIENT_B_AMOUNT"
                );
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = quoteLiquidity(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);
                require(
                    amountAOptimal >= amountAMin,
                    "BaseV1Router: INSUFFICIENT_A_AMOUNT"
                );
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    // @notice returns amounts of the tokens that will be deposited and the lp minted.
    function quoteZapIn(
        address tokenA,
        address tokenB,
        uint amountIn,
        bool stable
    ) external view returns (uint amountA, uint amountB, uint liquidity) {
        address _pair = pairFor(tokenA, tokenB, stable);
        uint swapAmount = calcSwap(tokenA, tokenB, amountIn, stable);
        uint fee = factory.pairFee(_pair) * 10000;
        fee = 10000 - (fee / 10000);
        amountB = getAmountOut(tokenA, tokenB, amountIn, stable);

        amountIn -= swapAmount;
        (amountA, amountB, liquidity) = quoteAddLiquidity(
            tokenA,
            tokenB,
            stable,
            amountA,
            amountB
        );
    }

    function calcSwap(
        address tokenA,
        address tokenB,
        uint amountA,
        bool stable
    ) public view returns (uint swapAmount) {
        address _pair = pairFor(tokenA, tokenB, stable);
        (
            uint decimals0,
            uint decimals1,
            uint reserve0,
            uint reserve1
        ) = getMetadata(tokenA, tokenB, _pair);
        uint fee = factory.pairFee(_pair) * 10000;
        swapAmount = stable
            ? _calcSwapStable(amountA, reserve0, reserve1, decimals0, decimals1)
            : _calcSwap(amountA, reserve0, fee);
    }

    function getAmountOut(
        address tokenA,
        address tokenB,
        uint amountA,
        bool stable
    ) public view returns (uint amountOut) {
        address _pair = pairFor(tokenA, tokenB, stable);
        (
            uint decimals0,
            uint decimals1,
            uint reserve0,
            uint reserve1
        ) = getMetadata(tokenA, tokenB, _pair);
        uint fee = factory.pairFee(_pair) * 10000;
        amountOut = getAmountOut(
            amountA * fee,
            stable,
            reserve0,
            reserve1,
            decimals0,
            decimals1
        );
    }

    function zapIn(
        address tokenA,
        address tokenB,
        uint amountA,
        bool stable,
        uint minLpOut
    ) public {
        address pair = pairFor(tokenA, tokenB, stable);
        IERC20Upgradeable(tokenA).transferFrom(
            msg.sender,
            address(this),
            amountA
        );
        amountA = IERC20Upgradeable(tokenA).balanceOf(address(this));
        (uint amountB, uint swapAmount) = _swap(
            tokenA,
            tokenB,
            amountA,
            stable,
            true
        );
        uint liquidity;

        if (!stable) {
            IERC20Upgradeable(tokenA).transfer(pair, amountA - swapAmount);
            IERC20Upgradeable(tokenB).transfer(pair, amountB);
            liquidity = IPair(pair).mint(msg.sender);
        } else {
            (uint amountAAfter, uint amountBAfter) = _addLiquidity(
                tokenA,
                tokenB,
                stable,
                amountA - swapAmount,
                amountB,
                0,
                0
            );
            IERC20Upgradeable(tokenA).transfer(pair, amountAAfter);
            IERC20Upgradeable(tokenB).transfer(pair, amountBAfter);
            liquidity = IPair(pair).mint(msg.sender);
            // refund dust
            uint dustA = amountA - swapAmount - amountAAfter;
            uint dustB = amountB - amountBAfter;
            if (dustA > 0) {
                IERC20Upgradeable(tokenA).transfer(msg.sender, dustA);
            }
            if (dustB > 0) {
                IERC20Upgradeable(tokenA).transfer(msg.sender, dustB);
            }
        }

        if (liquidity < minLpOut) {
            revert("Slippage");
        }
    }

    function zapInETH(
        address tokenB,
        bool stable,
        uint minLpOut
    ) external payable {
        address tokenA = address(weth);
        address pair = pairFor(tokenA, tokenB, stable);
        weth.deposit{value: msg.value}();
        uint256 amountA = IERC20Upgradeable(tokenA).balanceOf(address(this));
        (uint amountB, uint swapAmount) = _swap(
            tokenA,
            tokenB,
            amountA,
            stable,
            true
        );
        uint liquidity;

        if (!stable) {
            IERC20Upgradeable(tokenA).transfer(pair, amountA - swapAmount);
            IERC20Upgradeable(tokenB).transfer(pair, amountB);
            liquidity = IPair(pair).mint(msg.sender);
        } else {
            (uint amountAAfter, uint amountBAfter) = _addLiquidity(
                tokenA,
                tokenB,
                stable,
                amountA - swapAmount,
                amountB,
                0,
                0
            );
            IERC20Upgradeable(tokenA).transfer(pair, amountAAfter);
            IERC20Upgradeable(tokenB).transfer(pair, amountBAfter);
            liquidity = IPair(pair).mint(msg.sender);
            // refund dust
            uint dustA = amountA - swapAmount - amountAAfter;
            uint dustB = amountB - amountBAfter;
            if (dustA > 0) {
                IERC20Upgradeable(tokenA).transfer(msg.sender, dustA);
            }
            if (dustB > 0) {
                IERC20Upgradeable(tokenA).transfer(msg.sender, dustB);
            }
        }

        if (liquidity < minLpOut) {
            revert("Slippage");
        }
    }

    function swapTokens(
        uint amountIn,
        uint amountOutmin,
        route[] calldata routes,
        address to
    ) public returns (uint) {
        IERC20Upgradeable(routes[0].from).transferFrom(
            msg.sender,
            address(this),
            amountIn
        );
        address tokenB = routes[routes.length - 1].to;
        uint amountA;
        for (uint i; i < routes.length; ++i) {
            amountA = IERC20Upgradeable(routes[i].from).balanceOf(
                address(this)
            );
            _swap(
                routes[i].from,
                routes[i].to,
                amountA,
                routes[i].stable,
                false
            );
        }

        uint amountOut = IERC20Upgradeable(tokenB).balanceOf(address(this));
        require(amountOut >= amountOutmin, "slippage");
        if (to != address(this)) {
            IERC20Upgradeable(tokenB).transfer(to, amountOut);
        }
        return amountOut;
    }

    /*
     * @notice swaps tokens and zaps the output token to the output - tokenB pair
     */
    function swapTokensAndZap(
        uint amountIn,
        uint amountOutmin,
        route[] calldata routes,
        address tokenB,
        bool stable,
        uint minLpOut
    ) public {
        uint amountA = swapTokens(
            amountIn,
            amountOutmin,
            routes,
            address(this)
        );
        address tokenA = routes[routes.length - 1].to;
        address pair = pairFor(tokenA, tokenB, stable);

        (uint amountB, uint swapAmount) = _swap(
            tokenA,
            tokenB,
            amountA,
            stable,
            true
        );
        uint liquidity;

        if (!stable) {
            IERC20Upgradeable(tokenA).transfer(pair, amountA - swapAmount);
            IERC20Upgradeable(tokenB).transfer(pair, amountB);
            liquidity = IPair(pair).mint(msg.sender);
        } else {
            (uint amountAAfter, uint amountBAfter) = _addLiquidity(
                tokenA,
                tokenB,
                stable,
                amountA - swapAmount,
                amountB,
                0,
                0
            );
            IERC20Upgradeable(tokenA).transfer(pair, amountAAfter);
            IERC20Upgradeable(tokenB).transfer(pair, amountBAfter);
            liquidity = IPair(pair).mint(msg.sender);
            // refund dust
            uint dustA = amountA - swapAmount - amountAAfter;
            uint dustB = amountB - amountBAfter;
            if (dustA > 0) {
                IERC20Upgradeable(tokenA).transfer(msg.sender, dustA);
            }
            if (dustB > 0) {
                IERC20Upgradeable(tokenA).transfer(msg.sender, dustB);
            }
        }

        if (liquidity < minLpOut) {
            revert("Slippage");
        }
    }

    function swapETHAndZap(
        uint amountOutmin,
        route[] calldata routes,
        address tokenB,
        bool stable,
        uint minLpOut
    ) external payable {
        require(routes[0].from == address(weth), "Bad Route");
        uint256 amountIn = msg.value;
        weth.deposit{value: amountIn}();
        uint amountA = swapTokens(
            amountIn,
            amountOutmin,
            routes,
            address(this)
        );
        address tokenA = routes[routes.length - 1].to;
        address pair = pairFor(tokenA, tokenB, stable);

        (uint amountB, uint swapAmount) = _swap(
            tokenA,
            tokenB,
            amountA,
            stable,
            true
        );
        uint liquidity;

        if (!stable) {
            IERC20Upgradeable(tokenA).transfer(pair, amountA - swapAmount);
            IERC20Upgradeable(tokenB).transfer(pair, amountB);
            liquidity = IPair(pair).mint(msg.sender);
        } else {
            (uint amountAAfter, uint amountBAfter) = _addLiquidity(
                tokenA,
                tokenB,
                stable,
                amountA - swapAmount,
                amountB,
                0,
                0
            );
            IERC20Upgradeable(tokenA).transfer(pair, amountAAfter);
            IERC20Upgradeable(tokenB).transfer(pair, amountBAfter);
            liquidity = IPair(pair).mint(msg.sender);
            // refund dust
            uint dustA = amountA - swapAmount - amountAAfter;
            uint dustB = amountB - amountBAfter;
            if (dustA > 0) {
                IERC20Upgradeable(tokenA).transfer(msg.sender, dustA);
            }
            if (dustB > 0) {
                IERC20Upgradeable(tokenA).transfer(msg.sender, dustB);
            }
        }

        if (liquidity < minLpOut) {
            revert("Slippage");
        }
    }

    function _calcSwap(
        uint amountA,
        uint reserve0,
        uint fee
    ) internal pure returns (uint amount) {
        // (sqrt(((2 - f)r)^2 + 4(1 - f)ar) - (2 - f)r) / (2(1 - f))
        uint x = (2 * 10000) - fee / 10000;
        uint y = (4 * (10000 - (fee / 10000)) * 10000);
        uint z = 2 * (10000 - (fee / 10000));
        amount =
            (MathUpgradeable.sqrt(reserve0 * (x * x * reserve0 + amountA * y)) -
                reserve0 *
                x) /
            z;
    }

    function _calcSwapStable(
        uint amountA,
        uint reserve0,
        uint reserve1,
        uint decimals0,
        uint decimals1
    ) internal pure returns (uint amount) {
        // Credit to Tarot for this formula.
        uint a = (amountA * 10 ** 18) / decimals0;
        uint x = (reserve0 * 10 ** 18) / decimals0;
        uint y = (reserve1 * 10 ** 18) / decimals1;
        uint x2 = (x * x) / 10 ** 18;
        uint y2 = (y * y) / 10 ** 18;
        uint p = (y * ((((x2 * 3) + y2) * 10 ** 18) / ((y2 * 3) + x2))) / x;
        uint num = a * y;
        uint den = ((a + x) * p) / 10 ** 18 + y;

        amount = ((num / den) * decimals0) / 10 ** 18;
    }

    function _swap(
        address tokenA,
        address tokenB,
        uint amountA,
        bool stable,
        bool lp
    ) internal returns (uint, uint) {
        address pair = pairFor(tokenA, tokenB, stable);
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

        if (lp) {
            amountA = stable
                ? _calcSwapStable(
                    amountA,
                    reserve0,
                    reserve1,
                    decimals0,
                    decimals1
                )
                : _calcSwap(amountA, reserve0, fee);
        }

        IERC20Upgradeable(tokenA).transfer(pair, amountA);
        uint amountOut;
        amountOut = getAmountOut(
            amountA * fee,
            stable,
            reserve0,
            reserve1,
            decimals0,
            decimals1
        );
        // Checking actual balance of pair after transfer for full compatibility with tax tokens
        if (isTax[tokenA]) {
            uint pairBal = IERC20Upgradeable(tokenA).balanceOf(pair);
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
        if (isTax[tokenB])
            amountOut = IERC20Upgradeable(tokenB).balanceOf(address(this));
        return (amountOut, amountA);
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
        return amountB;
    }

    // k = xy(x^2 + y^2)
    function _k(
        uint x,
        uint y,
        uint decimals0,
        uint decimals1
    ) internal pure returns (uint) {
        uint _x = (x * 10 ** 18) / decimals0;
        uint _y = (y * 10 ** 18) / decimals1;
        uint _a = (_x * _y) / 10 ** 18;
        uint _b = ((_x * _x) / 10 ** 18 + (_y * _y) / 10 ** 18);
        return (_a * _b) / 10 ** 18;
    }

    function getY(uint x0, uint xy, uint y) internal pure returns (uint) {
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

