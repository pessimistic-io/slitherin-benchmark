// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./WhaleswapERC20.sol";
import "./Math.sol";
import "./UQ112x112.sol";
import "./IERC20.sol";
import "./WhaleswapFactory.sol";
import "./IWhaleswapCallee.sol";

contract WhaleswapPair is WhaleswapERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    // Used to denote stable or volatile pair, not immutable since construction happens in the initialize method for CREATE2 deterministic addresses
    bool public immutable stable;

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint private decimals0;
    uint private decimals1;
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'Whaleswap: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Whaleswap: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() {
        factory = msg.sender;

        (address _token0, address _token1, bool _stable) = WhaleswapFactory(msg.sender).getInitializable();
        (token0, token1, stable) = (_token0, _token1, _stable);

        if (_stable) {
            name = string(abi.encodePacked("Stable AMM - ", IERC20(_token0).symbol(), "/", IERC20(_token1).symbol()));
            symbol = string(abi.encodePacked("sAMM-", IERC20(_token0).symbol(), "/", IERC20(_token1).symbol()));
        } else {
            name = string(abi.encodePacked("Volatile AMM - ", IERC20(_token0).symbol(), "/", IERC20(_token1).symbol()));
            symbol = string(abi.encodePacked("vAMM-", IERC20(_token0).symbol(), "/", IERC20(_token1).symbol()));
        }

        decimals0 = 10**IERC20(_token0).decimals();
        decimals1 = 10**IERC20(_token1).decimals();
    }

    function _k(uint x, uint y) internal view returns (uint) {
        if (stable) {
            uint _x = x * 1e18 / decimals0;
            uint _y = y * 1e18 / decimals1;
            uint _a = (_x * _y) / 1e18;
            uint _b = ((_x * _x) / 1e18 + (_y * _y) / 1e18);
            return _a * _b / 1e18;  // x3y + y3x >= k
        } else {
            return x * y; // xy >= k
        }
    }

    function _f(uint x0, uint y) internal pure returns (uint) {
        return x0*(y*y/1e18*y/1e18)/1e18+(x0*x0/1e18*x0/1e18)*y/1e18;
    }

    function _d(uint x0, uint y) internal pure returns (uint) {
        return 3*x0*(y*y/1e18)/1e18+(x0*x0/1e18*x0/1e18);
    }

    function _get_y(uint x0, uint xy, uint y) internal pure returns (uint) {
        for (uint i = 0; i < 255; i++) {
            uint y_prev = y;
            uint k = _f(x0, y);
            if (k < xy) {
                uint dy = (xy - k)*1e18/_d(x0, y);
                y = y + dy;
            } else {
                uint dy = (k - xy)*1e18/_d(x0, y);
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

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'Whaleswap: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 5/25th (or 1/4th) of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = WhaleswapFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator;

                    // Dynamic fees for stable pairs
                    if(stable) {
                        numerator = numerator.mul(1);
                        denominator = rootK.mul(3).add(rootKLast.mul(1));
                    }
                    else {
                        numerator = numerator.mul(5);
                        denominator = rootK.mul(20).add(rootKLast.mul(5));
                    }
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'Whaleswap: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'Whaleswap: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, address tokenIn) external view returns (uint) {
        require(amountIn > 0, 'Whaleswap: INSUFFICIENT_INPUT_AMOUNT');
        require(tokenIn == token0 || tokenIn == token1);
        (uint112 _reserve0, uint112 _reserve1) = (reserve0, reserve1);

        // Remove fee from amount received
        if(stable) {
            amountIn = amountIn.mul(9996).div(10000);
        }
        else {
            amountIn = amountIn.mul(9975);
        }
        return _getAmountOut(amountIn, tokenIn, _reserve0, _reserve1);
    }

    function _getAmountOut(uint amountIn, address tokenIn, uint _reserve0, uint _reserve1) internal view returns (uint) {
        if (stable) {
            uint xy =  _k(_reserve0, _reserve1);
            _reserve0 = _reserve0 * 1e18 / decimals0;
            _reserve1 = _reserve1 * 1e18 / decimals1;
            (uint reserveA, uint reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
            amountIn = tokenIn == token0 ? amountIn * 1e18 / decimals0 : amountIn * 1e18 / decimals1;
            uint y = reserveB - _get_y(amountIn+reserveA, xy, reserveB);
            return y * (tokenIn == token0 ? decimals1 : decimals0) / 1e18;
        } else {
            (uint reserveA, uint reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
            return amountIn * reserveB / (reserveA.mul(10000).add(amountIn));
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, 'Whaleswap: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'Whaleswap: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
            (address _token0, address _token1) = (token0, token1);
            require(to != _token0 && to != _token1, 'Whaleswap: INVALID_TO');
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            if (data.length > 0) IWhaleswapCallee(to).whaleswapCall(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'Whaleswap: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint balance0Adjusted;
            uint balance1Adjusted;

            // Dynamic fees 🐳
            if(stable){
                balance0Adjusted = balance0.mul(10000).sub(amount0In.mul(4)); // 4 == 0.04% fee
                balance1Adjusted = balance1.mul(10000).sub(amount1In.mul(4));
            }
            else{
                balance0Adjusted = balance0.mul(10000).sub(amount0In.mul(25)); // 25 == 0.25% fee
                balance1Adjusted = balance1.mul(10000).sub(amount1In.mul(25));
            }

            // The curve, either x3y+y3x for stable pools, or x*y for volatile pools
            require(_k(balance0Adjusted, balance1Adjusted) >= _k(_reserve0, _reserve1).mul(10000**2), 'Whaleswap: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}

