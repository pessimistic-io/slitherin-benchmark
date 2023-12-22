// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IRouter.sol";
import "./IERC20.sol";


interface IFactory {
    function pairFee(address pair) external view returns (uint);
    function getFee(bool) external view returns(uint);
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address);
}
interface IPair {
    function metadata()
        external
        view
        returns (
            uint256 dec0,
            uint256 dec1,
            uint256 r0,
            uint256 r1,
            bool st,
            address t0,
            address t1
        );
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
}

// Swaps bribe/fee tokens to weth. Loosely based on Tarot optiswap. All swaps are made through ramses.
contract bribeSwappoor  {
    
    // token -> bridge token.
    mapping(address => address) tokenBridge;

    mapping(address => mapping(address => bool)) checkStable;
    address weth;
    IFactory factory;

    function initialize(address _weth, address _factory) external {
        weth = _weth;
        factory = IFactory(_factory);
    }

    function getBridgeToken(address _token) public view returns (address) {
       if (tokenBridge[_token] == address(0)){
           return weth;
       } 
       return tokenBridge[_token];
    }

    function addBridgeToken(address token, address bridge, bool stable) external {
        require(token != weth, "Nope");
        tokenBridge[token] = bridge;
        checkStable[token][bridge] = stable;
    }

    function removeBridge(address token, address bridge) external {
        require(token != weth);
        delete tokenBridge[token];
        delete checkStable[token][bridge];
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'BaseV1Router: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'BaseV1Router: ZERO_ADDRESS');
    }

    function _pairFor(address tokenA, address tokenB, bool stable) internal view returns (address pair) {
        pair = factory.getPair(tokenA, tokenB, stable);
    }

    function getAmountOut(
        uint amountA, 
        bool stable, 
        uint reserve0, 
        uint reserve1, 
        uint decimals0, 
        uint decimals1) public pure returns (uint) {
        
        uint amountB;
        // gas savings, ramses pair contract would revert anyway if amountOut under/overflows
        unchecked {
            if (!stable) {
                amountB = (amountA * reserve1) / (reserve0 * 10000 + amountA);
            } else {
                amountA = amountA / 10000;
                uint xy = _k(reserve0,reserve1,decimals0,decimals1);
                amountA = amountA * 10**18 / decimals0;
                uint y = (reserve1 * 10**18 / decimals1) - getY(amountA+(reserve0 * 10**18 / decimals0),xy,reserve1);
                amountB = y * decimals1 / 10**18;
            }
        }
        return amountB;
    }

    function getMetadata(address tokenA, address tokenB, address pair) internal view returns 
    (uint decimalsA, uint decimalsB,uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint decimals0, 
        uint decimals1,
        uint reserve0, 
        uint reserve1,,,) = IPair(pair).metadata();
        (decimalsA, decimalsB, reserveA, reserveB) = 
        tokenA == token0 ? (decimals0, decimals1,reserve0, reserve1) : (decimals1, decimals0, reserve1, reserve0);
    }

    function _swap(address tokenA, address tokenB, uint amountA, bool stable) internal returns(uint) {
        address pair = _pairFor(tokenA, tokenB, stable);
        uint fee = factory.pairFee(pair);
        if(fee == 0) {
            fee = factory.getFee(stable);
        }
        fee *= 10000;
        (uint decimals0,uint decimals1,uint reserve0,uint reserve1) = getMetadata(tokenA,tokenB,pair);
        
        unchecked {
            fee = 10000 - (fee  / 10000);
        }

        amountA = IERC20(tokenA).balanceOf(address(this));
        uint amountOut = getAmountOut(amountA * fee, stable, reserve0, reserve1, decimals0,decimals1);
        IERC20(tokenA).transfer(pair, amountA);
        if (tokenA < tokenB){
            IPair(pair).swap(0,amountOut,address(this),"");
        }else{
            IPair(pair).swap(amountOut,0,address(this),"");
        }
        return (amountOut);
    }

    function swapOptimal(address tokenA, address tokenB, uint amount) internal returns (uint) {
        address bridge;
        bool stable;

        bridge = getBridgeToken(tokenA);
        if(bridge == tokenB) {
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
        if (nextBridge == bridge) {
            stable = checkStable[nextBridge][tokenB];
            return _swap(nextBridge, tokenB, bridgeAmountOut, stable);
        } else if (bridge == tokenB) {
            return swapOptimal(nextBridge, tokenB, bridgeAmountOut);
        } else {
            stable = checkStable[bridge][nextBridge];
            uint nextBridgeAmount = _swap(bridge, nextBridge, bridgeAmountOut, stable);
            stable = checkStable[nextBridge][tokenB];
            return _swap(nextBridge,tokenB, nextBridgeAmount, stable);
        }
    }

    function swapTokens(address tokenA, address tokenB, uint amount) external {
        IERC20(tokenA).transferFrom(msg.sender, address(this), amount);
        uint amountOut = swapOptimal(tokenA, tokenB, amount);
        IERC20(tokenB).transfer(msg.sender, amountOut);
    }

    // Doing all calculations locally instead of calling router.

    // k = xy(x^2 + y^2)
    function _k(uint x, uint y,uint decimals0, uint decimals1) internal pure returns (uint) {
        unchecked{
            uint _x = x * 10**18 / decimals0;
            uint _y = y * 10**18 / decimals1;
            uint _a = (_x * _y) / 10**18;
            uint _b = ((_x * _x) + (_y * _y)) / 10**18;
            return _a * _b / 10**18; 
        }
    }


     function getY(uint x0, uint xy, uint y) internal pure returns (uint) {
        unchecked {
            for (uint i = 0; i < 255; ++i) {
                uint y_prev = y;
                uint k = _f(x0, y);
                if (k < xy) {
                    uint dy = (xy - k)*10**18/_d(x0, y);
                    y = y + dy;
                } else {
                    uint dy = (k - xy)*10**18/_d(x0, y);
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
        unchecked{
            uint x3 = (x0 * x0 * x0) / 10**36;
            uint y3 = (y * y * y) / 10**36;
            uint a = x0 * y3 /  10**18;
            uint b = x3 * y / 10**18;
            return a + b;
        }
    }

    function _d(uint x0, uint y) internal pure returns (uint) {
        unchecked{
            uint y2 = y* y;
            uint x3 = (x0 * x0 * x0) / 10**36;
            uint a = 3 * x0 * y2;
            return (a / 10**36) + x3;
        }
    }

}
