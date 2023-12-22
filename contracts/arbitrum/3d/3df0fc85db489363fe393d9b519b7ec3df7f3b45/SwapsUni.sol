// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";

error SwapsUni_PairDoesNotExist();

contract SwapsUni is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable owner;
    address private immutable FTM;
    address private immutable USDC;
    address private immutable ETH;
    address[] public routers;

    constructor(address _owner, address _usdc, address _eth, address[] memory _routers) {
        owner = _owner;
        routers = _routers;
        FTM = IUniswapV2Router02(_routers[0]).WETH();
        USDC = _usdc;
        ETH = _eth;
    }

    /**
     * @notice Calculate the percentage of a number.
     * @param x Number.
     * @param y Percentage of number.
     * @param scale Division.
     */
    function mulScale(
        uint256 x,
        uint256 y,
        uint128 scale
    ) internal pure returns (uint256) {
        uint256 a = x / scale;
        uint256 b = x % scale;
        uint256 c = y / scale;
        uint256 d = y % scale;

        return a * c * scale + a * d + b * c + (b * d) / scale;
    }

    /**
     * @notice Function that allows to send X amount of tokens and returns the token you want.
     * @param _tokenIn Address of the token to be swapped.
     * @param _amount Amount of Tokens to be swapped.
     * @param _tokenOut Contract of the token you wish to receive.
     * @param _amountOutMin Minimum amount you wish to receive.
     */
    function swapTokens(
        address _tokenIn,
        uint256 _amount,
        address _tokenOut,
        uint256 _amountOutMin
    ) public nonReentrant returns (uint256 _amountOut) {
        IUniswapV2Router02 routerIn = getRouterOneToken(_tokenIn);
        IUniswapV2Router02 routerOut = getRouterOneToken(_tokenOut);

        IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amount);

        address[] memory path;
        uint256[] memory amountsOut;

        if(_tokenIn != FTM && routerIn != routerOut) {
            IERC20(_tokenIn).safeApprove(address(routerIn), _amount);

            path = new address[](2);
            path[0] = _tokenIn;
            path[1] = FTM;

            amountsOut = routerIn.swapExactTokensForTokens(
                _amount,
                _amountOutMin,
                path,
                address(this),
                block.timestamp
            );

            _amount = amountsOut[amountsOut.length - 1];
            _tokenIn = FTM;
        }

        IERC20(_tokenIn).safeApprove(address(routerOut), 0);
        IERC20(_tokenIn).safeApprove(address(routerOut), _amount);

        if(_tokenIn != _tokenOut) {
            address tokenInPool_ = _getTokenPool(_tokenIn, routerOut);
            address tokenOutPool_ = _getTokenPool(_tokenOut, routerOut);
            if (_tokenIn == tokenOutPool_ || _tokenOut == tokenInPool_) {
                path = new address[](2);
                path[0] = _tokenIn;
                path[1] = _tokenOut;
            } else if(tokenInPool_ != tokenOutPool_) {
                path = new address[](4);
                path[0] = _tokenIn;
                path[1] = tokenInPool_;
                path[2] = tokenOutPool_;
                path[3] = _tokenOut;
            } else {
                path = new address[](3);
                path[0] = _tokenIn;
                path[1] = tokenInPool_;
                path[2] = _tokenOut;
            }
            
            amountsOut = routerOut.swapExactTokensForTokens(
                _amount,
                _amountOutMin,
                path,
                address(msg.sender),
                block.timestamp
            );

            _amountOut = amountsOut[amountsOut.length - 1];
        } else {
            _amountOut = _amount;
            IERC20(_tokenIn).safeTransfer(msg.sender, _amountOut);
        }
    }

    /**
    * @notice Function used to, given a token, get wich pool has more liquidity (FTM or UDSC)
    * @param _token  Address of input token
    * @param _router Router used to get pair tokens information
    */
    function _getTokenPool(address _token, IUniswapV2Router02 _router) internal view returns(address tokenPool) {
        address wftmTokenLp = IUniswapV2Factory(IUniswapV2Router02(_router).factory()).getPair(FTM, _token);
        address usdcTokenLp = IUniswapV2Factory(IUniswapV2Router02(_router).factory()).getPair(USDC, _token);
        address wftmUsdcLp = IUniswapV2Factory(IUniswapV2Router02(_router).factory()).getPair(FTM, USDC);
        address ethTokenLp = IUniswapV2Factory(IUniswapV2Router02(_router).factory()).getPair(ETH, _token);
        address wftmEthLp = IUniswapV2Factory(IUniswapV2Router02(_router).factory()).getPair(FTM, ETH);
        
        uint256 reservePairA1_;
        uint256 reservePairA2_;
        uint256 reserveWftm_;
        uint256 usdcToWftmAmount_;
        uint256 ethToWftmAmount_;
        address firstToken_;

        if(wftmTokenLp != address(0)) { 
            (reservePairA1_, reservePairA2_, ) = IUniswapV2Pair(wftmTokenLp).getReserves(); 
            firstToken_ = IUniswapV2Pair(wftmTokenLp).token0(); 
            if (FTM == firstToken_) { reserveWftm_ = reservePairA1_; } 
            else { reserveWftm_ = reservePairA2_; }
        }
        
        if(usdcTokenLp != address(0)) {
            uint256 reserveUsdc_;
            (reservePairA1_,reservePairA2_, ) = IUniswapV2Pair(usdcTokenLp).getReserves();
            firstToken_ = IUniswapV2Pair(usdcTokenLp).token0(); 
            if (USDC == firstToken_){ reserveUsdc_ = reservePairA1_; } 
            else { reserveUsdc_ = reservePairA2_; }

            (reservePairA1_,reservePairA2_,)  = IUniswapV2Pair(wftmUsdcLp).getReserves();
            usdcToWftmAmount_ = IUniswapV2Router02(_router).getAmountOut(reserveUsdc_, reservePairA1_, reservePairA2_);
        }

        if(ETH != FTM && ethTokenLp != address(0)) {
            uint256 reserveEth_;
            (reservePairA1_,reservePairA2_, ) = IUniswapV2Pair(ethTokenLp).getReserves();
            firstToken_ = IUniswapV2Pair(ethTokenLp).token0(); 
            if (ETH == firstToken_) { reserveEth_ = reservePairA1_; } 
            else { reserveEth_ = reservePairA2_; }

           (reservePairA1_,reservePairA2_, )  = IUniswapV2Pair(wftmEthLp).getReserves();
            ethToWftmAmount_ = IUniswapV2Router02(_router).getAmountOut(reserveEth_, reservePairA2_, reservePairA1_);
        }
        tokenPool = getTokenOutpool(reserveWftm_, usdcToWftmAmount_, ethToWftmAmount_);
    }

    /**
    * @notice Internal function used to, given reserves, calcualte the higher one
    */
    function getTokenOutpool(uint256 reserveWftm_, uint256 usdcToWftmAmount_, uint256  ethToWftmAmount_) internal view returns(address tokenPool) {
        if((reserveWftm_ >= usdcToWftmAmount_) && (reserveWftm_ >= ethToWftmAmount_)) {
            tokenPool = FTM;
        } else if (reserveWftm_ >= usdcToWftmAmount_) {
            if (reserveWftm_ < ethToWftmAmount_) {
                tokenPool = ETH;
            } else {
                tokenPool = FTM;
            }
        } else if (reserveWftm_ >= ethToWftmAmount_) {
            if (reserveWftm_ < usdcToWftmAmount_) {
                tokenPool = USDC;
            } else {
                tokenPool = FTM;
            }
        } else {
            if (ethToWftmAmount_ >= usdcToWftmAmount_) {
                tokenPool = ETH;
            } else { 
                tokenPool = USDC;
            }
        }
    }

    /**
    * @notice Function used to get a router of 2 tokens. It tries to get its main router
    * @param _token0 Address of the first token
    * @param _token1 Address of the second token
    */
    function getRouter(address _token0, address _token1) public view returns(IUniswapV2Router02 router) {
        address pairToken0;
        address pairToken1;
        for(uint8 i = 0; i < routers.length; i++) {
            if(_token0 == FTM || _token1 == FTM){
                router = IUniswapV2Router02(routers[i]);
                break;
            } else {
                pairToken0 = IUniswapV2Factory(IUniswapV2Router02(routers[i]).factory()).getPair(_token0, FTM);
                if(pairToken0 != address(0)) {
                    pairToken1 = IUniswapV2Factory(IUniswapV2Router02(routers[i]).factory()).getPair(_token1, FTM);
                }
            }
            if(pairToken1 != address(0)) {
                router = IUniswapV2Router02(routers[i]);
            }
        }

        if (address(router) == address(0)) revert SwapsUni_PairDoesNotExist();
    }

    /**
    * @notice Function used to get the router of a tokens. It tries to get its main router.
    * @param _token Address of the token
    */
    function getRouterOneToken(address _token) public view returns(IUniswapV2Router02 router) {
        address pair;
        for(uint8 i = 0; i < routers.length; i++) {
            if(_token == FTM){
                router = IUniswapV2Router02(routers[i]);
                break;
            } else {
                pair = IUniswapV2Factory(IUniswapV2Router02(routers[i]).factory()).getPair(_token, FTM);
                if(pair == address(0)) {
                    pair = IUniswapV2Factory(IUniswapV2Router02(routers[i]).factory()).getPair(_token, USDC);
                }
            }
            if(pair != address(0)) {
                router = IUniswapV2Router02(routers[i]);
            }
        }

        if (address(router) == address(0)) revert SwapsUni_PairDoesNotExist();
    }

    receive() external payable {}
}

