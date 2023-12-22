/*
                                           +##*:                                          
                                         .######-                                         
                                        .########-                                        
                                        *#########.                                       
                                       :##########+                                       
                                       *###########.                                      
                                      :############=                                      
                   *###################################################.                  
                   :##################################################=                   
                    .################################################-                    
                     .*#############################################-                     
                       =##########################################*.                      
                        :########################################=                        
                          -####################################=                          
                            -################################+.                           
               =##########################################################*               
               .##########################################################-               
                .*#######################################################:                
                  =####################################################*.                 
                   .*#################################################-                   
                     -##############################################=                     
                       -##########################################=.                      
                         :+####################################*-                         
           *###################################################################:          
           =##################################################################*           
            :################################################################=            
              =############################################################*.             
               .*#########################################################-               
                 :*#####################################################-                 
                   .=################################################+:                   
                      -+##########################################*-.                     
     .+*****************###########################################################*:     
      +############################################################################*.     
       :##########################################################################=       
         -######################################################################+.        
           -##################################################################+.          
             -*#############################################################=             
               :=########################################################+:               
                  :=##################################################+-                  
                     .-+##########################################*=:                     
                         .:=*################################*+-.                         
                              .:-=+*##################*+=-:.                              
                                     .:=*#########+-.                                     
                                         .+####*:                                         
                                           .*#:    */
// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
pragma abicoder v2;

import "./Pino.sol";
import "./IUniswap.sol";
import "./IWETH9.sol";
import "./INonfungiblePositionManager.sol";
import "./SafeERC20.sol";
import "./IERC721Receiver.sol";
import "./ISwapRouter.sol";

/// @title UniswapV3 proxy contract
/// @author Matin Kaboli
/// @notice Mints and Increases liquidity and swaps tokens
/// @dev This contract uses Permit2
contract Uniswap is IUniswap, Pino {
    using SafeERC20 for IERC20;

    event Mint(uint256 tokenId);

    ISwapRouter public immutable swapRouter;
    INonfungiblePositionManager public immutable nfpm;

    constructor(Permit2 _permit2, IWETH9 _weth, ISwapRouter _swapRouter, INonfungiblePositionManager _nfpm)
        Pino(_permit2, _weth)
    {
        nfpm = _nfpm;
        swapRouter = _swapRouter;
    }

    /// @inheritdoc IUniswap
    function swapExactInputSingle(IUniswap.SwapExactInputSingleParams calldata _params)
        external
        payable
        returns (uint256 amountOut)
    {
        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                fee: _params.fee,
                tokenIn: _params.tokenIn,
                tokenOut: _params.tokenOut,
                deadline: block.timestamp,
                amountIn: _params.amountIn,
                amountOutMinimum: _params.amountOutMinimum,
                sqrtPriceLimitX96: _params.sqrtPriceLimitX96,
                recipient: address(this)
            })
        );
    }

    /// @inheritdoc IUniswap
    function swapExactInputSingleETH(IUniswap.SwapExactInputSingleEthParams calldata _params, uint256 _proxyFee)
        external
        payable
        returns (uint256 amountOut)
    {
        uint256 value = msg.value - _proxyFee;

        amountOut = swapRouter.exactInputSingle{value: value}(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(WETH),
                tokenOut: _params.tokenOut,
                fee: _params.fee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: value,
                amountOutMinimum: _params.amountOutMinimum,
                sqrtPriceLimitX96: _params.sqrtPriceLimitX96
            })
        );
    }

    /// @inheritdoc IUniswap
    function swapExactOutputSingle(IUniswap.SwapExactOutputSingleParams calldata _params)
        external
        payable
        returns (uint256 amountIn)
    {
        amountIn = swapRouter.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: _params.tokenIn,
                tokenOut: _params.tokenOut,
                fee: _params.fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: _params.amountOut,
                amountInMaximum: _params.amountInMaximum,
                sqrtPriceLimitX96: _params.sqrtPriceLimitX96
            })
        );
    }

    /// @inheritdoc IUniswap
    function swapExactOutputSingleETH(IUniswap.SwapExactOutputSingleETHParams calldata _params, uint256 _proxyFee)
        external
        payable
        returns (uint256 amountIn)
    {
        uint256 value = msg.value - _proxyFee;

        amountIn = swapRouter.exactOutputSingle{value: value}(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: address(WETH),
                tokenOut: _params.tokenOut,
                fee: _params.fee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: _params.amountOut,
                amountInMaximum: value,
                sqrtPriceLimitX96: _params.sqrtPriceLimitX96
            })
        );
    }

    /// @inheritdoc IUniswap
    function swapExactInputMultihop(SwapExactInputMultihopParams calldata _params)
        external
        payable
        returns (uint256 amountOut)
    {
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: _params.path,
            deadline: block.timestamp,
            amountIn: _params.amountIn,
            amountOutMinimum: _params.amountOutMinimum,
            recipient: address(this)
        });

        amountOut = swapRouter.exactInput(swapParams);
    }

    /// @inheritdoc IUniswap
    function swapExactInputMultihopETH(SwapMultihopPath calldata _params, uint256 _proxyFee)
        external
        payable
        returns (uint256 amountOut)
    {
        uint256 value = msg.value - _proxyFee;

        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: _params.path,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: value,
            amountOutMinimum: _params.amountOutMinimum
        });

        amountOut = swapRouter.exactInput{value: value}(swapParams);
    }

    /// @inheritdoc IUniswap
    function swapExactOutputMultihop(SwapExactOutputMultihopParams calldata _params)
        external
        payable
        returns (uint256 amountIn)
    {
        ISwapRouter.ExactOutputParams memory swapParams = ISwapRouter.ExactOutputParams({
            path: _params.path,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _params.amountOut,
            amountInMaximum: _params.amountInMaximum
        });

        amountIn = swapRouter.exactOutput(swapParams);
    }

    /// @inheritdoc IUniswap
    function swapExactOutputMultihopETH(SwapExactOutputMultihopETHParams calldata _params, uint256 _proxyFee)
        external
        payable
        returns (uint256 amountIn)
    {
        uint256 value = msg.value - _proxyFee;

        ISwapRouter.ExactOutputParams memory swapParams = ISwapRouter.ExactOutputParams({
            path: _params.path,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: _params.amountOut,
            amountInMaximum: value
        });

        amountIn = swapRouter.exactOutput{value: value}(swapParams);
    }

    /// @inheritdoc IUniswap
    function swapExactInputMultihopMultiPool(SwapMultihopPath[] calldata _paths)
        external
        payable
        returns (uint256 amountOut)
    {
        amountOut = 0;

        for (uint8 i = 0; i < _paths.length;) {
            ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
                path: _paths[i].path,
                deadline: block.timestamp,
                amountIn: _paths[i].amountIn,
                recipient: address(this),
                amountOutMinimum: _paths[i].amountOutMinimum
            });

            uint256 exactAmountOut = swapRouter.exactInput(swapParams);

            amountOut += exactAmountOut;

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IUniswap
    function swapExactInputMultihopMultiPoolETH(SwapMultihopPath[] calldata _paths, uint256 _proxyFee)
        external
        payable
        returns (uint256 amountOut)
    {
        amountOut = 0;
        uint256 sumAmountsIn = 0;

        for (uint8 i = 0; i < _paths.length;) {
            ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
                path: _paths[i].path,
                deadline: block.timestamp,
                amountIn: _paths[i].amountIn,
                recipient: msg.sender,
                amountOutMinimum: _paths[i].amountOutMinimum
            });

            sumAmountsIn += _paths[i].amountIn;
            _require(sumAmountsIn <= msg.value - _proxyFee, ErrorCodes.ETHER_AMOUNT_SURPASSES_MSG_VALUE);

            uint256 exactAmountOut = swapRouter.exactInput{value: _paths[i].amountIn}(swapParams);
            amountOut += exactAmountOut;

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IUniswap
    function swapExactOutputMultihopMultiPool(SwapMultihopPath[] calldata _paths)
        external
        payable
        returns (uint256 amountIn)
    {
        amountIn = 0;

        for (uint8 i = 0; i < _paths.length;) {
            ISwapRouter.ExactOutputParams memory swapParams = ISwapRouter.ExactOutputParams({
                path: _paths[i].path,
                deadline: block.timestamp,
                amountInMaximum: _paths[i].amountIn,
                amountOut: _paths[i].amountOutMinimum,
                recipient: address(this)
            });

            uint256 exactAmountIn = swapRouter.exactOutput(swapParams);
            amountIn += exactAmountIn;

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IUniswap
    function swapExactOutputMultihopMultiPoolETH(SwapMultihopPath[] calldata _paths, uint256 _proxyFee)
        external
        payable
        returns (uint256 amountIn)
    {
        amountIn = 0;
        uint256 value = msg.value - _proxyFee;
        uint256 sumAmountsIn = 0;

        for (uint8 i = 0; i < _paths.length;) {
            ISwapRouter.ExactOutputParams memory swapParams = ISwapRouter.ExactOutputParams({
                path: _paths[i].path,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountInMaximum: _paths[i].amountIn,
                amountOut: _paths[i].amountOutMinimum
            });

            sumAmountsIn += _paths[i].amountIn;
            _require(sumAmountsIn <= value, ErrorCodes.ETHER_AMOUNT_SURPASSES_MSG_VALUE);

            uint256 amountUsed = swapRouter.exactOutput{value: _paths[i].amountIn}(swapParams);
            amountIn += amountUsed;

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IUniswap
    function mint(IUniswap.MintParams calldata _params, uint256 _proxyFee)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            fee: _params.fee,
            token0: _params.token0,
            token1: _params.token1,
            tickLower: _params.tickLower,
            tickUpper: _params.tickUpper,
            amount0Desired: _params.amount0Desired,
            amount1Desired: _params.amount1Desired,
            amount0Min: _params.amount0Min,
            amount1Min: _params.amount1Min,
            recipient: msg.sender,
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = nfpm.mint{value: msg.value - _proxyFee}(mintParams);

        nfpm.refundETH();
        nfpm.sweepToken(_params.token0, 0, msg.sender);
        nfpm.sweepToken(_params.token1, 0, msg.sender);

        emit Mint(tokenId);
    }

    /// @inheritdoc IUniswap
    function increaseLiquidity(IUniswap.IncreaseLiquidityParams calldata _params, uint256 _proxyFee)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        INonfungiblePositionManager.IncreaseLiquidityParams memory increaseParams = INonfungiblePositionManager
            .IncreaseLiquidityParams({
            tokenId: _params.tokenId,
            amount0Desired: _params.amountAdd0,
            amount1Desired: _params.amountAdd1,
            amount0Min: _params.amount0Min,
            amount1Min: _params.amount1Min,
            deadline: block.timestamp
        });

        (liquidity, amount0, amount1) = nfpm.increaseLiquidity{value: msg.value - _proxyFee}(increaseParams);

        nfpm.refundETH();
        nfpm.sweepToken(_params.token0, 0, msg.sender);
        nfpm.sweepToken(_params.token1, 0, msg.sender);
    }
}

