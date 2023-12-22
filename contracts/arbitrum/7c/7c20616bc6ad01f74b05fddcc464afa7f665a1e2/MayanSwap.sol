/**
 * Bridge provider adapter for Mayanswap
 * ** Note it should be delegate called to by the execution diamond contract!!!!! **
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./IBridgeProvider.sol";
import {StorageManagerFacet} from "./mayan_StorageManager.sol";
import {MayanData, MayanStorageManagerFacet} from "./mayan_StorageManager.sol";
import {MayanSwap} from "./src_MayanSwap.sol";
import {RelayerFees, Criteria, Recepient} from "./Types.sol";
import {IDataProvider} from "./IDataProvider.sol";
import "./console.sol";

contract MayanSwapAdapter is ITokenBridge {
    // ==============
    //     ERRORS
    // ==============
    error InsufficientBalance();

    // ==============
    //    METHDOS
    // ==============
    function bridgeHxroPayloadWithTokens(
        bytes32 token,
        uint256 amount,
        address msgSender,
        bytes calldata hxroPayload
    ) external returns (BridgeResult memory bridgeResult) {
        address srcToken = _getAndValidateSrcToken(token, amount);

        MayanData memory mayanData = MayanStorageManagerFacet(address(this))
            .getData(token);

        MayanSwap mayan = MayanStorageManagerFacet(address(this)).mayanswap();

        IERC20(srcToken).approve(address(mayan), amount);

        uint64 wormholeSequence = _swap(
            mayan,
            mayanData,
            msgSender,
            token,
            srcToken,
            amount,
            hxroPayload
        );

        bridgeResult = BridgeResult({
            id: Bridge.MAYAN_SWAP,
            trackableHash: abi.encode(wormholeSequence)
        });
    }

    // ==============
    //    INTERNAL
    // ==============
    function _swap(
        MayanSwap mayan,
        MayanData memory mayanData,
        address msgSender,
        bytes32 token,
        address srcToken,
        uint256 amount,
        bytes memory hxroPayload
    ) internal returns (uint64 wormholeSeq) {
        wormholeSeq = mayan.swap(
            _getRelayerFees(mayanData, srcToken),
            _getRecepient(mayanData, msgSender),
            token,
            1, // @TODO Support Non-solana native tokens. Need to either use some Wormhole mapping as source of info or map on our own
            _gerCriteria(amount, hxroPayload),
            srcToken,
            amount
        );
    }

    function _getAndValidateSrcToken(
        bytes32 solToken,
        uint256 swapAmt
    ) internal view returns (address srcToken) {
        srcToken = StorageManagerFacet(address(this)).getSourceToken(solToken);

        if (IERC20(srcToken).balanceOf(address(this)) > swapAmt)
            revert InsufficientBalance();

        if (srcToken == address(0)) revert UnsupportedToken();
    }

    function _getRelayerFees(
        MayanData memory mayanData,
        address srcToken
    ) internal view returns (MayanSwap.RelayerFees memory relayerFees) {
        // Get swap fee
        uint256 requiredSolForSwap = mayanData.solConstantFee;

        IDataProvider dataProvider = StorageManagerFacet(address(this))
            .getDataProvider();

        uint256 tokenSwapFee = dataProvider.quoteSOLToToken(
            srcToken,
            requiredSolForSwap
        );

        uint256 refundFee = dataProvider.quoteETHToToken(
            srcToken,
            mayanData.refundFee
        );

        // If it's too small we just got to do it like this
        if (refundFee == 0) refundFee = tokenSwapFee / 2;

        relayerFees = MayanSwap.RelayerFees({
            swapFee: uint64(tokenSwapFee),
            redeemFee: 0,
            refundFee: uint64(refundFee)
        });
    }

    function _gerCriteria(
        uint256 amountIn,
        bytes memory hxroPayload
    ) internal view returns (MayanSwap.Criteria memory criteria) {
        uint256 deadline = block.timestamp + 12 hours;
        uint256 amountOutMin = amountIn - (amountIn / 3);

        criteria = MayanSwap.Criteria({
            transferDeadline: deadline,
            swapDeadline: uint64(deadline),
            amountOutMin: uint64(amountOutMin),
            unwrap: false,
            gasDrop: 0,
            customPayload: hxroPayload
        });
    }

    function _getRecepient(
        MayanData memory mayanData,
        address msgSender
    ) internal view returns (MayanSwap.Recepient memory recepient) {
        bytes32 hxroProgram = StorageManagerFacet(address(this))
            .getSolanaProgram();

        recepient = MayanSwap.Recepient({
            mayanAddr: mayanData.ata,
            mayanChainId: mayanData.solChainId,
            auctionAddr: mayanData.mayanSolAuctionProgram,
            destAddr: hxroProgram,
            destChainId: mayanData.solChainId,
            referrer: 0x1111111111111111111111111111111111111111111111111111111111111111,
            refundAddr: bytes32(uint256(uint160(msgSender)))
        });
    }
}

