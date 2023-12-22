/*
    Copyright 2022 https://www.dzap.io
    SPDX-License-Identifier: MIT
*/
pragma solidity 0.8.17;

import "./SafeERC20.sol";

import "./IAggregationRouterV4.sol";
import "./IWNATIVE.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";

import "./FeeModule.sol";
import "./Permitable.sol";
import "./Math.sol";
import "./ISwapHandler.sol";

import { Router, FeeType, Token, SwapInfo, SwapDescription, SwapDetails, TransferDetails, TransferInfo, LpSwapDetails, WNativeSwapDetails, LPSwapInfo, OutputLp, UnoSwapDetails, InputTokenData } from "./Types.sol";

abstract contract SwapHandler is FeeModule, Permitable, ISwapHandler {
    using SafeERC20 for IERC20;

    mapping(address => Router) public routers;

    address public immutable wNative;
    address public immutable AGGREGATION_ROUTER;

    IERC20 private constant _ZERO_ADDRESS = IERC20(address(0));
    IERC20 private constant _ETH_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    uint256 private constant _PARTIAL_FILL = 1 << 0;

    /* ========= CONSTRUCTOR ========= */

    constructor(
        address[] memory routers_,
        Router[] memory routerDetails_,
        address aggregationRouter_,
        address wNative_
    ) {
        require(wNative_ != address(0) && aggregationRouter_ != address(0), "DZS0015");

        AGGREGATION_ROUTER = aggregationRouter_;
        wNative = wNative_;

        for (uint256 i; i < routers_.length; ++i) {
            address router = routers_[i];
            require(router != address(0), "DZS0016");
            routers[router] = routerDetails_[i];
        }
    }

    /* ========= VIEWS ========= */

    function calculateOptimalSwapAmount(
        uint256 amountA_,
        uint256 amountB_,
        uint256 reserveA_,
        uint256 reserveB_,
        address router_
    ) public view returns (uint256) {
        require(amountA_ * reserveB_ >= amountB_ * reserveA_, "DZS0014");

        uint256 routerFeeBps = routers[router_].fees;
        uint256 a = BPS_DENOMINATOR - routerFeeBps;
        uint256 b = (((BPS_DENOMINATOR * 2) - routerFeeBps)) * reserveA_;
        uint256 _c = (amountA_ * reserveB_) - (amountB_ * reserveA_);
        uint256 c = ((_c * BPS_DENOMINATOR) / (amountB_ + reserveB_)) * reserveA_;

        uint256 d = a * c * 4;
        uint256 e = Math.sqrt((b * b) + d);

        uint256 numerator = e - b;
        uint256 denominator = a * 2;

        return numerator / denominator;
    }

    /* ========= RESTRICTED ========= */

    function updateRouters(address[] calldata routers_, Router[] calldata routerDetails_) external onlyGovernance {
        for (uint256 i; i < routers_.length; ++i) {
            address router = routers_[i];
            require(router != address(0), "DZS0016");
            routers[router] = routerDetails_[i];
        }

        emit RoutersUpdated(routers_, routerDetails_);
    }

    /* ========= PUBLIC ========= */

    // can return both native and wNative
    function swapTokensToTokens(
        SwapDetails[] calldata data_,
        address recipient_,
        uint256 projectId_,
        uint256 nftId_
    ) external payable {
        require(recipient_ != address(0), "DZS001");
        SwapInfo[] memory swapInfo = new SwapInfo[](data_.length);
        (uint256 tempProtocolFeeBps, uint256 tempProjectFeeBps, address projectFeeVault) = _getFeeDetail(
            projectId_,
            nftId_,
            FeeType.BATCH_SWAP
        );

        for (uint256 i; i < data_.length; ++i) {
            SwapDetails memory data = data_[i];

            require(data.desc.dstReceiver == address(0), "DZS002");
            require(data.desc.flags & _PARTIAL_FILL == 0, "DZS003");

            uint256 value;

            if (_isNative(data.desc.srcToken)) {
                value = data.desc.amount;
            } else {
                _transferAndApprove(data.permit, data.desc.srcToken, AGGREGATION_ROUTER, data.desc.amount);
            }

            try
                IAggregationRouterV4(AGGREGATION_ROUTER).swap{ value: value }(data.executor, data.desc, data.routeData)
            returns (uint256 returnAmount, uint256) {
                require(returnAmount >= data.desc.minReturnAmount, "DZS004");

                swapInfo[i] = SwapInfo(data.desc.srcToken, data.desc.dstToken, data.desc.amount, returnAmount);

                _swapTransferDstTokens(
                    data.desc.dstToken,
                    recipient_,
                    projectFeeVault,
                    returnAmount,
                    tempProtocolFeeBps,
                    tempProjectFeeBps
                );
            } catch Error(string memory) {
                swapInfo[i] = SwapInfo(data.desc.srcToken, data.desc.dstToken, data.desc.amount, 0);
                if (_isNative(data.desc.srcToken)) {
                    _safeNativeTransfer(_msgSender(), data.desc.amount);
                } else {
                    data.desc.srcToken.safeApprove(AGGREGATION_ROUTER, 0);
                    data.desc.srcToken.safeTransfer(_msgSender(), data.desc.amount);
                }
            }
        }

        emit TokensSwapped(_msgSender(), recipient_, swapInfo, [tempProtocolFeeBps, tempProjectFeeBps]);
    }

    // can return only native when dest is wNative
    function unoSwapTokensToTokens(
        UnoSwapDetails[] calldata swapData_,
        address recipient_,
        uint256 projectId_,
        uint256 nftId_
    ) external payable {
        require(recipient_ != address(0), "DZS001");
        SwapInfo[] memory swapInfo = new SwapInfo[](swapData_.length);

        (uint256 tempProtocolFeeBps, uint256 tempProjectFeeBps, address projectFeeVault) = _getFeeDetail(
            projectId_,
            nftId_,
            FeeType.BATCH_SWAP
        );

        _nativeDeposit();

        // lp swap
        for (uint256 i; i < swapData_.length; ++i) {
            UnoSwapDetails memory data = swapData_[i];

            IERC20 srcToken = IERC20(data.path[0]);
            IERC20 dstToken = IERC20(data.path[data.path.length - 1]);

            require(!_isNative(dstToken), "DZS008");

            if (_isNative(srcToken)) {
                data.path[0] = wNative;
                IWNATIVE(wNative).approve(data.router, data.amount);
            } else {
                _transferAndApprove(data.permit, srcToken, data.router, data.amount);
            }

            try
                IUniswapV2Router02(data.router).swapExactTokensForTokens(
                    data.amount,
                    data.minReturnAmount,
                    data.path,
                    address(this),
                    block.timestamp + 60
                )
            returns (uint256[] memory amountOuts) {
                uint256 returnAmount = amountOuts[amountOuts.length - 1];

                require(returnAmount >= data.minReturnAmount, "DZS004");

                swapInfo[i] = SwapInfo(srcToken, dstToken, data.amount, returnAmount);

                _unoSwapTransferDstTokens(
                    dstToken,
                    recipient_,
                    projectFeeVault,
                    returnAmount,
                    tempProtocolFeeBps,
                    tempProjectFeeBps
                );
            } catch Error(string memory) {
                swapInfo[i] = SwapInfo(srcToken, dstToken, data.amount, 0);

                if (_isNative(srcToken)) {
                    IWNATIVE(wNative).withdraw(data.amount);
                    _safeNativeTransfer(_msgSender(), data.amount);
                } else {
                    srcToken.safeApprove(data.router, 0);
                    srcToken.safeTransfer(_msgSender(), data.amount);
                }
            }
        }

        emit TokensSwapped(_msgSender(), recipient_, swapInfo, [tempProtocolFeeBps, tempProjectFeeBps]);
    }

    // can return both native and wNative
    function swapLpToTokens(
        LpSwapDetails[] calldata lpSwapDetails_,
        WNativeSwapDetails[] calldata wEthSwapDetails_,
        address recipient_,
        uint256 projectId_,
        uint256 nftId_
    ) external {
        require(recipient_ != address(0), "DZS001");
        require(wEthSwapDetails_.length > 0, "DZS009");

        // as in the final swap all the wNative tokens are considered
        // require(IWNATIVE(wNative).balanceOf(address(this)) == 0, "DZS0010");

        LPSwapInfo memory swapInfo;
        swapInfo.lpInput = new Token[](lpSwapDetails_.length);
        swapInfo.lpOutput = new Token[](wEthSwapDetails_.length + 1);

        (uint256 tempProtocolFeeBps, uint256 tempProjectFeeBps, address projectFeeVault) = _getFeeDetail(
            projectId_,
            nftId_,
            FeeType.BATCH_SWAP_LP
        );

        // swap lp to weth
        swapInfo.lpInput = _swapLpToWNative(lpSwapDetails_);

        // swap weth to tokens
        swapInfo.lpOutput = _swapWNativeToDstTokens(
            wEthSwapDetails_,
            recipient_,
            projectFeeVault,
            IWNATIVE(wNative).balanceOf(address(this)),
            tempProtocolFeeBps,
            tempProjectFeeBps
        );

        emit LpSwapped(_msgSender(), recipient_, swapInfo, [tempProtocolFeeBps, tempProjectFeeBps]);
    }

    function swapTokensToLp(
        SwapDetails[] calldata data_,
        LpSwapDetails[] calldata lpSwapDetails_,
        OutputLp calldata outputLpDetails_,
        address recipient_,
        uint256 projectId_,
        uint256 nftId_
    ) public payable {
        require(recipient_ != address(0), "DZS001");
        require(routers[outputLpDetails_.router].isSupported, "DZS005");

        Token[] memory input = new Token[](data_.length + lpSwapDetails_.length + 1);
        (uint256 tempProtocolFeeBps, uint256 tempProjectFeeBps, address projectFeeVault) = _getFeeDetail(
            projectId_,
            nftId_,
            FeeType.BATCH_SWAP_LP
        );

        address token0 = IUniswapV2Pair(outputLpDetails_.lpToken).token0();
        address token1 = IUniswapV2Pair(outputLpDetails_.lpToken).token1();
        uint256 i;

        // native to wNative
        if (msg.value > 0) {
            IWNATIVE(wNative).deposit{ value: msg.value }();
            input[input.length - 1] = Token(address(0), msg.value);
        }

        // erc to wNative
        for (i; i < data_.length; ++i) {
            SwapDetails memory data = data_[i];
            address srcToken = address(data.desc.srcToken);

            if (srcToken != wNative && srcToken != token0 && srcToken != token1) {
                require(data.desc.dstReceiver == address(0), "DZS002");
                require(data.desc.flags & _PARTIAL_FILL == 0, "DZS003"); // partial fill not allowed
                require(!_isNative(data.desc.srcToken), "DZS0011"); // src cant be native
                require(data.desc.dstToken == IERC20(wNative), "DZS0012");

                _transferAndApprove(data.permit, data.desc.srcToken, AGGREGATION_ROUTER, data.desc.amount);

                (uint256 returnAmount, ) = IAggregationRouterV4(AGGREGATION_ROUTER).swap(
                    data.executor,
                    data.desc,
                    data.routeData
                );

                require(returnAmount > data.desc.minReturnAmount, "DZS004");
            } else {
                _permit(srcToken, data.permit);
                data.desc.srcToken.safeTransferFrom(_msgSender(), address(this), data.desc.amount);
            }

            input[i] = Token(srcToken, data.desc.amount);
        }

        // lp to wNative
        for (uint256 j; j < lpSwapDetails_.length; ++j) {
            LpSwapDetails memory details = lpSwapDetails_[j];
            require(routers[details.router].isSupported, "DZS0013");
            // require(outputLpDetails_.lpToken != details.token, "DZS0014");

            address tokenA = IUniswapV2Pair(details.token).token0();
            address tokenB = IUniswapV2Pair(details.token).token1();

            (uint256 amountA, uint256 amountB) = _removeLiquidity(details, tokenA, tokenB, details.router);

            _swapExactTokensForTokens(
                tokenA,
                amountA,
                details.tokenAToPath,
                tokenA != wNative && tokenA != token0 && tokenA != token1,
                details.router
            );
            _swapExactTokensForTokens(
                tokenB,
                amountB,
                details.tokenBToPath,
                tokenB != wNative && tokenB != token0 && tokenB != token1,
                details.router
            );

            input[i + j] = Token(details.token, details.amount);
        }

        uint256[3] memory returnAmounts = _addOptimalLiquidity(outputLpDetails_, token0, token1);

        require(returnAmounts[0] >= outputLpDetails_.minReturnAmount, "DZS004");

        _transferOutputLP(
            IERC20(outputLpDetails_.lpToken),
            recipient_,
            projectFeeVault,
            returnAmounts[0],
            tempProtocolFeeBps,
            tempProjectFeeBps
        );

        // Transfer dust
        if (returnAmounts[1] > 0) {
            IERC20(token0).safeTransfer(_msgSender(), returnAmounts[1]);
        }
        if (returnAmounts[2] > 0) {
            IERC20(token1).safeTransfer(_msgSender(), returnAmounts[2]);
        }

        emit LiquidityAdded(
            _msgSender(),
            recipient_,
            input,
            outputLpDetails_.lpToken,
            returnAmounts,
            [tempProtocolFeeBps, tempProjectFeeBps]
        );
    }

    function batchTransfer(
        TransferDetails[] calldata data_,
        uint256 projectId_,
        uint256 nftId_
    ) external payable {
        TransferInfo[] memory transferInfo = new TransferInfo[](data_.length);

        (uint256 tempProtocolFeeBps, uint256 tempProjectFeeBps, address projectFeeVault) = _getFeeDetail(
            projectId_,
            nftId_,
            FeeType.BATCH_TRANSFER
        );
        uint256 availableBalance = msg.value;

        for (uint256 i; i < data_.length; ++i) {
            TransferDetails memory details = data_[i];
            require(details.recipient != address(0), "DZS001");
            Token[] memory tokenInfo = new Token[](details.data.length);

            for (uint256 j; j < details.data.length; ++j) {
                InputTokenData memory data = details.data[j];
                (uint256 amountAfterFee, uint256 protocolFee, uint256 projectFee) = _calculateFeeAmount(
                    data.amount,
                    tempProtocolFeeBps,
                    tempProjectFeeBps
                );

                tokenInfo[j] = Token(address(data.token), data.amount);

                if (_isNative(data.token)) {
                    require(availableBalance >= data.amount, "DZS003");
                    availableBalance -= data.amount;
                    _safeNativeTransfer(details.recipient, amountAfterFee);
                    if (protocolFee > 0) _safeNativeTransfer(protocolFeeVault, protocolFee);
                    if (projectFee > 0) _safeNativeTransfer(projectFeeVault, projectFee);
                } else {
                    _permit(address(data.token), data.permit);

                    data.token.safeTransferFrom(_msgSender(), details.recipient, amountAfterFee);
                    if (protocolFee > 0) data.token.safeTransferFrom(_msgSender(), protocolFeeVault, protocolFee);
                    if (projectFee > 0) data.token.safeTransferFrom(_msgSender(), projectFeeVault, projectFee);
                }
            }
            transferInfo[i] = TransferInfo(details.recipient, tokenInfo);
        }

        require(availableBalance == 0, "DZS006");

        emit TokensTransferred(_msgSender(), transferInfo, [tempProtocolFeeBps, tempProjectFeeBps]);
    }

    /* ========= INTERNAL/PRIVATE ========= */

    function _isNative(IERC20 token_) internal pure returns (bool) {
        return (token_ == _ZERO_ADDRESS || token_ == _ETH_ADDRESS);
    }

    function _safeNativeTransfer(address to_, uint256 amount_) internal {
        (bool sent, ) = to_.call{ value: amount_ }(new bytes(0));
        require(sent, "DZS007");
    }

    function _nativeDeposit() private {
        if (msg.value > 0) {
            IWNATIVE(wNative).deposit{ value: msg.value }();
        }
    }

    function _transferAndApprove(
        bytes memory permit_,
        IERC20 srcToken_,
        address router_,
        uint256 amount_
    ) private {
        _permit(address(srcToken_), permit_);
        srcToken_.safeTransferFrom(_msgSender(), address(this), amount_);
        srcToken_.safeApprove(router_, amount_);
    }

    function _swapTransferDstTokens(
        IERC20 token_,
        address recipient_,
        address projectFeeVault,
        uint256 returnAmount,
        uint256 tempProtocolFeeBps,
        uint256 tempProjectFeeBps
    ) private {
        (uint256 amountAfterFee, uint256 protocolFee, uint256 projectFee) = _calculateFeeAmount(
            returnAmount,
            tempProtocolFeeBps,
            tempProjectFeeBps
        );

        if (_isNative(token_)) {
            _safeNativeTransfer(recipient_, amountAfterFee);
            if (protocolFee > 0) _safeNativeTransfer(protocolFeeVault, protocolFee);
            if (projectFee > 0) _safeNativeTransfer(projectFeeVault, projectFee);
        } else {
            token_.safeTransfer(recipient_, amountAfterFee);
            if (protocolFee > 0) token_.safeTransfer(protocolFeeVault, protocolFee);
            if (projectFee > 0) token_.safeTransfer(projectFeeVault, projectFee);
        }
    }

    function _unoSwapTransferDstTokens(
        IERC20 token_,
        address recipient_,
        address projectFeeVault,
        uint256 returnAmount,
        uint256 tempProtocolFeeBps,
        uint256 tempProjectFeeBps
    ) private {
        (uint256 amountAfterFee, uint256 protocolFee, uint256 projectFee) = _calculateFeeAmount(
            returnAmount,
            tempProtocolFeeBps,
            tempProjectFeeBps
        );

        if (address(token_) == wNative) {
            IWNATIVE(wNative).withdraw(returnAmount);
            _safeNativeTransfer(recipient_, amountAfterFee);
            if (protocolFee > 0) _safeNativeTransfer(protocolFeeVault, protocolFee);
            if (projectFee > 0) _safeNativeTransfer(projectFeeVault, projectFee);
        } else {
            token_.safeTransfer(recipient_, amountAfterFee);
            if (protocolFee > 0) token_.safeTransfer(protocolFeeVault, protocolFee);
            if (projectFee > 0) token_.safeTransfer(projectFeeVault, projectFee);
        }
    }

    function _transferOutputLP(
        IERC20 lpToken,
        address recipient_,
        address projectFeeVault,
        uint256 returnAmount,
        uint256 tempProtocolFeeBps,
        uint256 tempProjectFeeBps
    ) private {
        (uint256 amountAfterFee, uint256 protocolFee, uint256 projectFee) = _calculateFeeAmount(
            returnAmount,
            tempProtocolFeeBps,
            tempProjectFeeBps
        );

        lpToken.safeTransfer(recipient_, amountAfterFee);
        if (protocolFee > 0) lpToken.safeTransfer(protocolFeeVault, protocolFee);
        if (projectFee > 0) lpToken.safeTransfer(projectFeeVault, projectFee);
    }

    function _swapWNativeForToken(
        uint256 amount_,
        address[] memory path_,
        address router_
    ) private returns (uint256) {
        IWNATIVE(wNative).approve(router_, amount_);

        uint256[] memory amountOuts = IUniswapV2Router02(router_).swapExactTokensForTokens(
            amount_,
            0,
            path_,
            address(this),
            block.timestamp + 60
        );
        return amountOuts[amountOuts.length - 1];
    }

    function _swapExactTokensForTokens(
        address token_,
        uint256 amount_,
        address[] memory path_,
        bool executeSwap_,
        address router_
    ) private {
        if (executeSwap_) {
            IERC20(token_).approve(router_, amount_);
            IUniswapV2Router02(router_).swapExactTokensForTokens(
                amount_,
                0,
                path_,
                address(this),
                block.timestamp + 60
            );
        }
    }

    //  used in swapLpToTokens
    function _swapLpToWNative(LpSwapDetails[] calldata lpSwapDetails_) internal returns (Token[] memory) {
        Token[] memory swapInfo = new Token[](lpSwapDetails_.length);

        for (uint256 i; i < lpSwapDetails_.length; ++i) {
            LpSwapDetails memory details = lpSwapDetails_[i];
            require(routers[details.router].isSupported, "DZS005");

            address tokenA = IUniswapV2Pair(details.token).token0();
            address tokenB = IUniswapV2Pair(details.token).token1();

            (uint256 amountA, uint256 amountB) = _removeLiquidity(details, tokenA, tokenB, details.router);

            _swapExactTokensForTokens(tokenA, amountA, details.tokenAToPath, tokenA != wNative, details.router);

            _swapExactTokensForTokens(tokenB, amountB, details.tokenBToPath, tokenB != wNative, details.router);

            swapInfo[i] = Token(details.token, details.amount);
        }

        return swapInfo;
    }

    //  used in swapLpToTokens
    function _swapWNativeToDstTokens(
        WNativeSwapDetails[] calldata wEthSwapDetails_,
        address recipient_,
        address projectFeeVault,
        uint256 wNativeBalance,
        uint256 tempProtocolFeeBps,
        uint256 tempProjectFeeBps
    ) private returns (Token[] memory) {
        Token[] memory swapInfo = new Token[](wEthSwapDetails_.length);

        // swap weth to tokens
        // for last swap all the leftOver tokens are considered
        for (uint256 i; i < wEthSwapDetails_.length; ++i) {
            WNativeSwapDetails memory details = wEthSwapDetails_[i];

            uint256 wNativeAmount = i != wEthSwapDetails_.length - 1
                ? (wNativeBalance * details.sizeBps) / BPS_DENOMINATOR
                : IWNATIVE(wNative).balanceOf(address(this));

            if (details.nativeToOutputPath.length == 0) {
                // native

                require(wNativeAmount >= details.minReturnAmount, "DZS004");

                (uint256 amountAfterFee, uint256 protocolFee, uint256 projectFee) = _calculateFeeAmount(
                    wNativeAmount,
                    tempProtocolFeeBps,
                    tempProjectFeeBps
                );

                IWNATIVE(wNative).withdraw(wNativeAmount);
                _safeNativeTransfer(recipient_, amountAfterFee);
                if (protocolFee > 0) _safeNativeTransfer(protocolFeeVault, protocolFee);
                if (projectFee > 0) _safeNativeTransfer(projectFeeVault, projectFee);

                swapInfo[i] = Token(address(0), wNativeAmount);
            } else {
                // wNative and others
                address destToken = details.nativeToOutputPath[details.nativeToOutputPath.length - 1];

                uint256 amountOut = wNativeAmount;

                if (destToken != wNative) {
                    require(routers[details.router].isSupported, "DZS005");
                    amountOut = _swapWNativeForToken(wNativeAmount, details.nativeToOutputPath, details.router);
                }

                require(amountOut >= details.minReturnAmount, "DZS004");

                (uint256 amountAfterFee, uint256 protocolFee, uint256 projectFee) = _calculateFeeAmount(
                    amountOut,
                    tempProtocolFeeBps,
                    tempProjectFeeBps
                );

                IERC20(destToken).safeTransfer(recipient_, amountAfterFee);
                if (protocolFee > 0) IERC20(destToken).safeTransfer(protocolFeeVault, protocolFee);
                if (projectFee > 0) IERC20(destToken).safeTransfer(projectFeeVault, projectFee);

                swapInfo[i] = Token(destToken, amountOut);
            }
        }

        return swapInfo;
    }

    function _removeLiquidity(
        LpSwapDetails memory details_,
        address tokenA_,
        address tokenB_,
        address router_
    ) private returns (uint256 amountA, uint256 amountB) {
        _transferAndApprove(details_.permit, IERC20(details_.token), router_, details_.amount);

        (amountA, amountB) = IUniswapV2Router02(router_).removeLiquidity(
            tokenA_,
            tokenB_,
            details_.amount,
            0,
            0,
            address(this),
            block.timestamp + 60
        );
    }

    function _addOptimalLiquidity(
        OutputLp calldata lpDetails_,
        address tokenA_,
        address tokenB_
    ) private returns (uint256[3] memory) {
        uint256 wNativeBalance = IWNATIVE(wNative).balanceOf(address(this));

        // swap 50-50
        if (wNativeBalance > 0) {
            if (tokenA_ != wNative)
                _swapWNativeForToken(wNativeBalance / 2, lpDetails_.nativeToToken0, lpDetails_.router);

            if (tokenB_ != wNative)
                _swapWNativeForToken(
                    wNativeBalance - (wNativeBalance / 2),
                    lpDetails_.nativeToToken1,
                    lpDetails_.router
                );
        }

        // do optimal swap
        (uint256 amountA, uint256 amountB) = _optimalSwapForAddingLiquidity(
            lpDetails_.lpToken,
            tokenA_,
            tokenB_,
            IERC20(tokenA_).balanceOf(address(this)),
            IERC20(tokenB_).balanceOf(address(this)),
            lpDetails_.router
        );

        IERC20(tokenA_).approve(lpDetails_.router, amountA);
        IERC20(tokenB_).approve(lpDetails_.router, amountB);

        // add liquidity
        (uint256 addedToken0, uint256 addedToken1, uint256 lpAmount) = IUniswapV2Router02(lpDetails_.router)
            .addLiquidity(tokenA_, tokenB_, amountA, amountB, 0, 0, address(this), block.timestamp + 60);

        return ([lpAmount, amountA - addedToken0, amountB - addedToken1]);
    }

    function _optimalSwapForAddingLiquidity(
        address lp,
        address tokenA_,
        address tokenB_,
        uint256 amountA_,
        uint256 amountB_,
        address router_
    ) private returns (uint256, uint256) {
        (uint256 reserveA, uint256 reserveB, ) = IUniswapV2Pair(lp).getReserves();

        if (reserveA * amountB_ == reserveB * amountA_) {
            return (amountA_, amountB_);
        }

        bool reverse = reserveA * amountB_ > reserveB * amountA_;

        uint256 optimalSwapAmount = reverse
            ? calculateOptimalSwapAmount(amountB_, amountA_, reserveB, reserveA, router_)
            : calculateOptimalSwapAmount(amountA_, amountB_, reserveA, reserveB, router_);

        address[] memory path = new address[](2);
        (path[0], path[1]) = reverse ? (tokenB_, tokenA_) : (tokenA_, tokenB_);

        if (optimalSwapAmount > 0) {
            IERC20(path[0]).approve(router_, optimalSwapAmount);

            uint256[] memory amountOuts = IUniswapV2Router02(router_).swapExactTokensForTokens(
                optimalSwapAmount,
                0,
                path,
                address(this),
                block.timestamp + 60
            );

            if (reverse) {
                amountA_ += amountOuts[amountOuts.length - 1];
                amountB_ -= optimalSwapAmount;
            } else {
                amountA_ -= optimalSwapAmount;
                amountB_ += amountOuts[amountOuts.length - 1];
            }
        }

        return (amountA_, amountB_);
    }
}

