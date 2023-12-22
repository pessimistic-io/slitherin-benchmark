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

import "./Proxy.sol";
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
contract Uniswap is IUniswap, Proxy {
    using SafeERC20 for IERC20;

    event Mint(uint256 tokenId);

    ISwapRouter public immutable swapRouter;
    INonfungiblePositionManager public immutable nfpm;

    constructor(
        Permit2 _permit2,
        IWETH9 _weth,
        ISwapRouter _swapRouter,
        INonfungiblePositionManager _nfpm,
        IERC20[] memory _tokens
    ) Proxy(_permit2, _weth) {
        nfpm = _nfpm;
        swapRouter = _swapRouter;

        for (uint8 i = 0; i < _tokens.length; ++i) {
            _tokens[i].safeApprove(address(_nfpm), type(uint256).max);
            _tokens[i].safeApprove(address(_swapRouter), type(uint256).max);
        }
    }

    /// @inheritdoc IUniswap
    function swapExactInputSingle(
        IUniswap.SwapExactInputSingleParams calldata _params,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature
    ) external payable returns (uint256 amountOut) {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                fee: _params.fee,
                tokenIn: _permit.permitted.token,
                tokenOut: _params.tokenOut,
                deadline: block.timestamp,
                amountIn: _permit.permitted.amount,
                amountOutMinimum: _params.amountOutMinimum,
                sqrtPriceLimitX96: _params.sqrtPriceLimitX96,
                recipient: _params.receiveETH ? address(this) : msg.sender
            })
        );

        if (_params.receiveETH) {
            _unwrapWETH9(msg.sender);
        }
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
    function swapExactOutputSingle(
        IUniswap.SwapExactOutputSingleParams calldata _params,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature
    ) external payable returns (uint256 amountIn) {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        amountIn = swapRouter.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: _permit.permitted.token,
                tokenOut: _params.tokenOut,
                fee: _params.fee,
                recipient: _params.receiveETH ? address(this) : msg.sender,
                deadline: block.timestamp,
                amountOut: _params.amountOut,
                amountInMaximum: _permit.permitted.amount,
                sqrtPriceLimitX96: _params.sqrtPriceLimitX96
            })
        );

        if (_params.receiveETH) {
            _unwrapWETH9(msg.sender);
        }

        _sweepToken(_permit.permitted.token);
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

        if (amountIn < value) {
            _sendETH(msg.sender, value - amountIn);
        }
    }

    /// @inheritdoc IUniswap
    function swapExactInputMultihop(
        SwapExactInputMultihopParams calldata _params,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature
    ) external payable returns (uint256 amountOut) {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: _params.path,
            deadline: block.timestamp,
            amountIn: _permit.permitted.amount,
            amountOutMinimum: _params.amountOutMinimum,
            recipient: _params.receiveETH ? address(this) : msg.sender
        });

        amountOut = swapRouter.exactInput(swapParams);

        if (_params.receiveETH) {
            _unwrapWETH9(msg.sender);
        }

        _sweepToken(_permit.permitted.token);
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
    function swapExactOutputMultihop(
        SwapExactOutputMultihopParams calldata _params,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature
    ) external payable returns (uint256 amountIn) {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        ISwapRouter.ExactOutputParams memory swapParams = ISwapRouter.ExactOutputParams({
            path: _params.path,
            recipient: _params.receiveETH ? address(this) : msg.sender,
            deadline: block.timestamp,
            amountOut: _params.amountOut,
            amountInMaximum: _permit.permitted.amount
        });

        amountIn = swapRouter.exactOutput(swapParams);

        if (_params.receiveETH) {
            _unwrapWETH9(msg.sender);
        }

        _sweepToken(_permit.permitted.token);
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

        if (amountIn < value) {
            _sendETH(msg.sender, value - amountIn);
        }
    }

    /// @inheritdoc IUniswap
    function swapExactInputMultihopMultiPool(
        SwapMultihopMultiPoolParams calldata _params,
        SwapMultihopPath[] calldata _paths,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature
    ) external payable returns (uint256) {
        uint256 amountOut = 0;

        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        for (uint8 i = 0; i < _paths.length;) {
            ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
                path: _paths[i].path,
                deadline: block.timestamp,
                amountIn: _paths[i].amountIn,
                recipient: _params.receiveETH ? address(this) : msg.sender,
                amountOutMinimum: _paths[i].amountOutMinimum
            });

            uint256 exactAmountOut = swapRouter.exactInput(swapParams);

            amountOut += exactAmountOut;

            unchecked {
                ++i;
            }
        }

        if (_params.receiveETH) {
            _unwrapWETH9(msg.sender);
        }

        return amountOut;
    }

    /// @inheritdoc IUniswap
    function swapExactInputMultihopMultiPoolETH(SwapMultihopPath[] calldata _paths, uint256 _proxyFee)
        external
        payable
        returns (uint256)
    {
        uint256 amountOut = 0;
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
            _require(sumAmountsIn <= msg.value - _proxyFee, Errors.ETHER_AMOUNT_SURPASSES_MSG_VALUE);

            uint256 exactAmountOut = swapRouter.exactInput{value: _paths[i].amountIn}(swapParams);
            amountOut += exactAmountOut;

            unchecked {
                ++i;
            }
        }

        return amountOut;
    }

    /// @inheritdoc IUniswap
    function swapExactOutputMultihopMultiPool(
        SwapMultihopMultiPoolParams calldata _params,
        SwapMultihopPath[] calldata _paths,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature
    ) external payable returns (uint256) {
        uint256 amountIn = 0;

        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        for (uint8 i = 0; i < _paths.length;) {
            ISwapRouter.ExactOutputParams memory swapParams = ISwapRouter.ExactOutputParams({
                path: _paths[i].path,
                deadline: block.timestamp,
                amountInMaximum: _paths[i].amountIn,
                amountOut: _paths[i].amountOutMinimum,
                recipient: _params.receiveETH ? address(this) : msg.sender
            });

            uint256 exactAmountIn = swapRouter.exactOutput(swapParams);
            amountIn += exactAmountIn;

            unchecked {
                ++i;
            }
        }

        if (_params.receiveETH) {
            _unwrapWETH9(msg.sender);
        }

        _sweepToken(_permit.permitted.token);

        return amountIn;
    }

    /// @inheritdoc IUniswap
    function swapExactOutputMultihopMultiPoolETH(SwapMultihopPath[] calldata _paths, uint256 _proxyFee)
        external
        payable
        returns (uint256)
    {
        uint256 amountIn = 0;
        uint256 value = msg.value - _proxyFee;
        uint256 sumAmountsIn = 0;
        uint256 sumAmountsUsed = 0;

        for (uint8 i = 0; i < _paths.length;) {
            ISwapRouter.ExactOutputParams memory swapParams = ISwapRouter.ExactOutputParams({
                path: _paths[i].path,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountInMaximum: _paths[i].amountIn,
                amountOut: _paths[i].amountOutMinimum
            });

            sumAmountsIn += _paths[i].amountIn;
            _require(sumAmountsIn <= value, Errors.ETHER_AMOUNT_SURPASSES_MSG_VALUE);

            uint256 amountUsed = swapRouter.exactOutput{value: _paths[i].amountIn}(swapParams);
            sumAmountsUsed += amountUsed;
            amountIn += amountUsed;

            unchecked {
                ++i;
            }
        }

        if (sumAmountsUsed < value) {
            _sendETH(msg.sender, value - sumAmountsUsed);
        }

        return amountIn;
    }

    /// @inheritdoc IUniswap
    function mint(
        IUniswap.MintParams calldata _params,
        uint256 _proxyFee,
        ISignatureTransfer.PermitBatchTransferFrom calldata _permit,
        bytes calldata _signature
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        uint256 tokensLen = _permit.permitted.length;

        require(_permit.permitted[0].token == _params.token0);

        ISignatureTransfer.SignatureTransferDetails[] memory details =
            new ISignatureTransfer.SignatureTransferDetails[](tokensLen);

        details[0].to = address(this);
        details[0].requestedAmount = _permit.permitted[0].amount;

        // Assume that _permit.permitted.length == 1
        address token1 = address(WETH);
        uint256 amount1Desired = msg.value - _proxyFee;

        if (tokensLen > 1) {
            details[1].to = address(this);
            details[1].requestedAmount = _permit.permitted[1].amount;

            token1 = _permit.permitted[1].token;
            amount1Desired = _permit.permitted[1].amount;
        } else {
            if (_params.token0 == address(WETH) || _params.token1 == address(WETH)) {
                WETH.deposit{value: amount1Desired}();
            }
        }

        _require(token1 == _params.token1, Errors.TOKENS_MISMATCHED);

        permit2.permitTransferFrom(_permit, details, msg.sender, _signature);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            fee: _params.fee,
            token0: _params.token0,
            token1: _params.token1,
            tickLower: _params.tickLower,
            tickUpper: _params.tickUpper,
            amount0Desired: _permit.permitted[0].amount,
            amount1Desired: amount1Desired,
            amount0Min: _params.amount0Min,
            amount1Min: _params.amount1Min,
            recipient: msg.sender,
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = nfpm.mint(mintParams);

        if (amount0 < _permit.permitted[0].amount) {
            _send(_permit.permitted[0].token, msg.sender, _permit.permitted[0].amount - amount0);
        }

        if (amount1 < amount1Desired) {
            uint256 refund1 = amount1Desired - amount1;

            if (tokensLen > 1) {
                _send(token1, msg.sender, refund1);
            } else {
                WETH.withdraw(refund1);

                _sendETH(msg.sender, refund1);
            }
        }

        emit Mint(tokenId);
    }

    /// @inheritdoc IUniswap
    function increaseLiquidity(
        IUniswap.IncreaseLiquidityParams calldata _params,
        uint256 _proxyFee,
        ISignatureTransfer.PermitBatchTransferFrom calldata _permit,
        bytes calldata _signature
    ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        uint256 tokensLen = _permit.permitted.length;

        ISignatureTransfer.SignatureTransferDetails[] memory details =
            new ISignatureTransfer.SignatureTransferDetails[](tokensLen);

        details[0].to = address(this);
        details[0].requestedAmount = _permit.permitted[0].amount;

        if (tokensLen > 1) {
            details[1].to = address(this);
            details[1].requestedAmount = _permit.permitted[1].amount;
        }

        permit2.permitTransferFrom(_permit, details, msg.sender, _signature);

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

        if (amount0 < _params.amountAdd0) {
            if (_params.token0 == address(WETH) && msg.value > _proxyFee) {
                _sendETH(msg.sender, _params.amountAdd0 - amount0);
            } else {
                _sweepToken(_params.token0);
            }
        }

        if (amount1 < _params.amountAdd1) {
            if (_params.token1 == address(WETH) && msg.value > _proxyFee) {
                _sendETH(msg.sender, _params.amountAdd1 - amount1);
            } else {
                _sweepToken(_params.token1);
            }
        }
    }
}

