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
                                           .*#:    
*/
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

    /// @notice Represents the deposit of an NFT
    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    ISwapRouter public immutable swapRouter;
    mapping(uint256 => Deposit) public deposits;
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

    // @notice Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    // function onERC721Received(address operator, address, uint256 tokenId, bytes calldata)
    //     external
    //     override
    //     returns (bytes4)
    // {
    //     _createDeposit(operator, tokenId);
    //
    //     return this.onERC721Received.selector;
    // }

    // function _createDeposit(address owner, uint256 tokenId) internal {
    //     (,, address token0, address token1,,,, uint128 liquidity,,,,) = nfpm.positions(tokenId);
    //
    //     deposits[tokenId] = Deposit({owner: owner, liquidity: liquidity, token0: token0, token1: token1});
    // }

    /// @inheritdoc IUniswap
    function swapExactInputSingle(
        IUniswap.SwapExactInputSingleParams calldata params,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external payable returns (uint256) {
        if (params.receiveETH) {
            require(params.tokenOut == address(WETH), "Token out must be WETH");
        }

        permit2.permitTransferFrom(
            permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: permit.permitted.amount}),
            msg.sender,
            signature
        );

        uint256 amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                fee: params.fee,
                tokenIn: permit.permitted.token,
                tokenOut: params.tokenOut,
                deadline: block.timestamp,
                amountIn: permit.permitted.amount,
                amountOutMinimum: params.amountOutMinimum,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96,
                recipient: params.receiveETH ? address(this) : msg.sender
            })
        );

        if (params.receiveETH) {
            WETH.withdraw(amountOut);
            (bool sent,) = payable(msg.sender).call{value: amountOut}("");
            require(sent, "Failed to send Ether");
        }

        return amountOut;
    }

    /// @inheritdoc IUniswap
    function swapExactInputSingleETH(IUniswap.SwapExactInputSingleEthParams calldata params, uint256 proxyFee)
        external
        payable
        returns (uint256)
    {
        uint256 value = msg.value - proxyFee;

        return swapRouter.exactInputSingle{value: value}(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(WETH),
                tokenOut: params.tokenOut,
                fee: params.fee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: value,
                amountOutMinimum: params.amountOutMinimum,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );
    }

    /// @inheritdoc IUniswap
    function swapExactOutputSingle(
        IUniswap.SwapExactOutputSingleParams calldata params,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external payable returns (uint256) {
        permit2.permitTransferFrom(
            permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: permit.permitted.amount}),
            msg.sender,
            signature
        );

        uint256 amountIn = swapRouter.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: permit.permitted.token,
                tokenOut: params.tokenOut,
                fee: params.fee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: params.amountOut,
                amountInMaximum: permit.permitted.amount,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        if (amountIn < permit.permitted.amount) {
            IERC20(permit.permitted.token).safeTransfer(msg.sender, permit.permitted.amount - amountIn);
        }

        return amountIn;
    }

    /// @inheritdoc IUniswap
    function swapExactInputMultihop(
        SwapExactInputMultihopParams calldata params,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external payable returns (uint256 amountOut) {
        permit2.permitTransferFrom(
            permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: permit.permitted.amount}),
            msg.sender,
            signature
        );

        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: params.path,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: permit.permitted.amount,
            amountOutMinimum: params.amountOutMinimum
        });

        amountOut = swapRouter.exactInput(swapParams);
    }

    /// @inheritdoc IUniswap
    function swapExactInputMultihopETH(SwapExactInputMultihopETHParams calldata params, uint256 proxyFee)
        external
        payable
        returns (uint256 amountOut)
    {
        uint256 value = msg.value - proxyFee;

        WETH.deposit{value: value}();

        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: params.path,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: value,
            amountOutMinimum: params.amountOutMinimum
        });

        amountOut = swapRouter.exactInput(swapParams);
    }

    /// @inheritdoc IUniswap
    function swapExactOutputMultihop(
        SwapExactOutputMultihopParams calldata params,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external payable returns (uint256 amountIn) {
        permit2.permitTransferFrom(
            permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: permit.permitted.amount}),
            msg.sender,
            signature
        );

        ISwapRouter.ExactOutputParams memory swapParams = ISwapRouter.ExactOutputParams({
            path: params.path,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: params.amountOut,
            amountInMaximum: permit.permitted.amount
        });

        amountIn = swapRouter.exactOutput(swapParams);

        if (amountIn < permit.permitted.amount) {
            IERC20(permit.permitted.token).safeTransfer(msg.sender, permit.permitted.amount - amountIn);
        }
    }

    /// @inheritdoc IUniswap
    function swapExactOutputMultihopETH(SwapExactOutputMultihopETHParams calldata params, uint256 proxyFee)
        external
        payable
        returns (uint256 amountIn)
    {
        uint256 value = msg.value - proxyFee;
        WETH.deposit{value: value}();

        ISwapRouter.ExactOutputParams memory swapParams = ISwapRouter.ExactOutputParams({
            path: params.path,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: params.amountOut,
            amountInMaximum: value
        });

        amountIn = swapRouter.exactOutput(swapParams);

        if (amountIn < value) {
            WETH.withdraw(value - amountIn);

            (bool success,) = payable(msg.sender).call{value: value - amountIn}("");
            require(success, "Failed to send back eth");
        }
    }

    /// @inheritdoc IUniswap
    function mint(
        IUniswap.MintParams calldata params,
        uint256 proxyFee,
        ISignatureTransfer.PermitBatchTransferFrom calldata permit,
        bytes calldata signature
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        uint256 tokensLen = permit.permitted.length;

        require(permit.permitted[0].token == params.token0);

        ISignatureTransfer.SignatureTransferDetails[] memory details =
            new ISignatureTransfer.SignatureTransferDetails[](tokensLen);

        details[0].to = address(this);
        details[0].requestedAmount = permit.permitted[0].amount;

        // Assume that permit.permitted.length == 1
        address token1 = address(WETH);
        uint256 amount1Desired = msg.value - proxyFee;

        if (tokensLen > 1) {
            details[1].to = address(this);
            details[1].requestedAmount = permit.permitted[1].amount;

            token1 = permit.permitted[1].token;
            amount1Desired = permit.permitted[1].amount;
        } else {
            if (params.token0 == address(WETH) || params.token1 == address(WETH)) {
                WETH.deposit{value: amount1Desired}();
            }
        }

        require(token1 == params.token1);

        permit2.permitTransferFrom(permit, details, msg.sender, signature);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            fee: params.fee,
            token0: params.token0,
            token1: params.token1,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            amount0Desired: permit.permitted[0].amount,
            amount1Desired: amount1Desired,
            amount0Min: params.amount0Min,
            amount1Min: params.amount1Min,
            recipient: msg.sender,
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = nfpm.mint(mintParams);

        if (amount0 < permit.permitted[0].amount) {
            uint256 refund0 = permit.permitted[0].amount - amount0;

            IERC20(permit.permitted[0].token).safeTransfer(msg.sender, refund0);
        }

        if (amount1 < amount1Desired) {
            uint256 refund1 = amount1Desired - amount1;

            if (tokensLen > 1) {
                IERC20(token1).safeTransfer(msg.sender, refund1);
            } else {
                WETH.withdraw(refund1);
                (bool success,) = payable(msg.sender).call{value: refund1}("");

                require(success, "Failed to send back eth");
            }
        }

        emit Mint(tokenId);
    }

    // /// @inheritdoc IUniswap
    // function collect(IUniswap.CollectParams calldata params)
    //     external
    //     payable
    //     returns (uint256 amount0, uint256 amount1)
    // {
    //     INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
    //         tokenId: params.tokenId,
    //         recipient: msg.sender,
    //         amount0Max: params.amount0Max,
    //         amount1Max: params.amount1Max
    //     });
    //
    //     (amount0, amount1) = nfpm.collect(collectParams);
    //
    //     _sendToOwner(params.tokenId, amount0, amount1);
    // }

    /// @inheritdoc IUniswap
    function increaseLiquidity(
        IUniswap.IncreaseLiquidityParams calldata params,
        uint256 proxyFee,
        ISignatureTransfer.PermitBatchTransferFrom calldata permit,
        bytes calldata signature
    ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        uint256 tokensLen = permit.permitted.length;

        ISignatureTransfer.SignatureTransferDetails[] memory details =
            new ISignatureTransfer.SignatureTransferDetails[](tokensLen);

        details[0].to = address(this);
        details[0].requestedAmount = permit.permitted[0].amount;

        if (tokensLen > 1) {
            details[1].to = address(this);
            details[1].requestedAmount = permit.permitted[1].amount;
        }

        permit2.permitTransferFrom(permit, details, msg.sender, signature);

        INonfungiblePositionManager.IncreaseLiquidityParams memory increaseParams = INonfungiblePositionManager
            .IncreaseLiquidityParams({
            tokenId: params.tokenId,
            amount0Desired: params.amountAdd0,
            amount1Desired: params.amountAdd1,
            amount0Min: params.amount0Min,
            amount1Min: params.amount1Min,
            deadline: block.timestamp
        });

        (liquidity, amount0, amount1) = nfpm.increaseLiquidity{value: msg.value - proxyFee}(increaseParams);
    }

    // /// @inheritdoc IUniswap
    // function decreaseLiquidity(IUniswap.DecreaseLiquidityParams calldata params)
    //     external
    //     payable
    //     returns (uint256 amount0, uint256 amount1)
    // {
    //     INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams = INonfungiblePositionManager
    //         .DecreaseLiquidityParams({
    //         tokenId: params.tokenId,
    //         liquidity: params.liquidity,
    //         amount0Min: params.amount0Min,
    //         amount1Min: params.amount1Min,
    //         deadline: block.timestamp
    //     });
    //
    //     (amount0, amount1) = nfpm.decreaseLiquidity(decreaseParams);
    //
    //     _sendToOwner(params.tokenId, amount0, amount1);
    // }

    /// @notice Transfers funds to owner of NFT
    /// @param _tokenId The id of the erc721
    /// @param _amount0 The amount of token0
    /// @param _amount1 The amount of token1
    function _sendToOwner(uint256 _tokenId, uint256 _amount0, uint256 _amount1) internal {
        (, address owner, address token0, address token1,,,,,,,,) = nfpm.positions(_tokenId);

        IERC20(token0).safeTransfer(owner, _amount0);
        IERC20(token1).safeTransfer(owner, _amount1);
    }
}

