// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import { SwapInfo, LPSwapInfo, Token, TransferInfo, Router, SwapDetails, UnoSwapDetails, LpSwapDetails, WNativeSwapDetails, OutputLp, TransferDetails } from "./Types.sol";

import "./IFeeModule.sol";

interface ISwapHandler is IFeeModule {
    /* ========= EVENTS ========= */

    event RoutersUpdated(address[] routers, Router[] details);

    event TokensSwapped(address indexed sender, address indexed recipient, SwapInfo[] swapInfo, uint256[2] feeBps); // protocolFeeBps, projectFeeBPS

    event LpSwapped(address indexed sender, address indexed recipient, LPSwapInfo swapInfo, uint256[2] feeBps);

    event LiquidityAdded(
        address indexed sender,
        address indexed recipient,
        Token[] inputTokens, // both erc20 and lp
        address outputLp,
        uint256[3] returnAmounts, // outputLP, unspentAmount0, unspentAmount1
        uint256[2] feeBps
    );

    event TokensTransferred(address indexed sender, TransferInfo[] details, uint256[2] feeBps);

    /* ========= VIEWS ========= */

    function calculateOptimalSwapAmount(
        uint256 amountA_,
        uint256 amountB_,
        uint256 reserveA_,
        uint256 reserveB_,
        address router_
    ) external view returns (uint256);

    /* ========= RESTRICTED ========= */

    function updateRouters(address[] calldata routers_, Router[] calldata routerDetails_) external;

    /* ========= PUBLIC ========= */

    function swapTokensToTokens(
        SwapDetails[] calldata data_,
        address recipient_,
        uint256 projectId_,
        uint256 nftId_
    ) external payable;

    function unoSwapTokensToTokens(
        UnoSwapDetails[] calldata swapData_,
        address recipient_,
        uint256 projectId_,
        uint256 nftId_
    ) external payable;

    function swapLpToTokens(
        LpSwapDetails[] calldata lpSwapDetails_,
        WNativeSwapDetails[] calldata wEthSwapDetails_,
        address recipient_,
        uint256 projectId_,
        uint256 nftId_
    ) external;

    function swapTokensToLp(
        SwapDetails[] calldata data_,
        LpSwapDetails[] calldata lpSwapDetails_,
        OutputLp calldata outputLpDetails_,
        address recipient_,
        uint256 projectId_,
        uint256 nftId_
    ) external payable;

    function batchTransfer(
        TransferDetails[] calldata data_,
        uint256 projectId_,
        uint256 nftId_
    ) external payable;
}

