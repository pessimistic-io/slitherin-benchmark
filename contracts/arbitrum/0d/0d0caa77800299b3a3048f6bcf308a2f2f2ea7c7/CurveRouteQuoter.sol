// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.9;

import "./IRouteQuoterParameters.sol";
import "./Protocols.sol";
import "./ICurvePool.sol";

contract CurveRouteQuoter is IRouteQuoterParameters {
    struct CurveQuoteExactInputSingleParameters {
        /// @dev The protocol identifier
        uint8 protocol;
        /// @dev The address of the Curve pool contract that the quote is being requested for
        address poolAddress;
        /// @dev The index of the input token in the Curve pool
        uint8 tokenInIndex;
        /// @dev The index of the output token in the Curve pool
        uint8 tokenOutIndex;
        /// @dev The amount of the input token that is being swapped
        uint256 amountIn;
        /// @dev The address of the swap contract that will be used to execute the token swap.
        address swapAddress;
    }

    function CurveQuoteExactInputSingle(
        CurveQuoteExactInputSingleParameters memory parameters
    ) internal view returns (QuoteExactResult memory result) {
        result.amountToPay = parameters.amountIn;
        uint256 gasBefore = gasleft();
        if (parameters.protocol == Protocols.CURVE1) {
            result.amountOut = ICurvePool(parameters.poolAddress).get_dy(
                int128(int8(parameters.tokenInIndex)),
                int128(int8(parameters.tokenOutIndex)),
                parameters.amountIn
            );
        } else if (parameters.protocol == Protocols.CURVE2) {
            result.amountOut = ICurvePool(parameters.poolAddress).get_dy_underlying(
                int128(int8(parameters.tokenInIndex)),
                int128(int8(parameters.tokenOutIndex)),
                parameters.amountIn
            );
        } else if (parameters.protocol == Protocols.CURVE3) {
            result.amountOut = ICurveCryptoPool(parameters.poolAddress).get_dy(
                uint256(parameters.tokenInIndex),
                uint256(parameters.tokenOutIndex),
                parameters.amountIn
            );
        } else if (parameters.protocol == Protocols.CURVE4) {
            result.amountOut = ICurveCryptoPool(parameters.poolAddress).get_dy_underlying(
                uint256(parameters.tokenInIndex),
                uint256(parameters.tokenOutIndex),
                parameters.amountIn
            );
        } else if (parameters.protocol == Protocols.CURVE7) {
            uint256[2] memory _amounts;
            _amounts[parameters.tokenInIndex] = parameters.amountIn;
            result.amountOut = ICurveBasePool2Coins(parameters.poolAddress).calc_token_amount(_amounts, true);
        } else if (parameters.protocol == Protocols.CURVE8 || parameters.protocol == Protocols.CURVE9) {
            uint256[3] memory _amounts;
            _amounts[parameters.tokenInIndex] = parameters.amountIn;
            result.amountOut = ICurveBasePool3Coins(parameters.poolAddress).calc_token_amount(_amounts, true);
        } else if (parameters.protocol == Protocols.CURVE10 || parameters.protocol == Protocols.CURVE11) {
            result.amountOut = ICurveBasePool3Coins(parameters.poolAddress).calc_withdraw_one_coin(
                parameters.amountIn,
                int128(int8(parameters.tokenOutIndex))
            );
        } else {
            // CRQ_IP: invalid protocol
            revert("CRQ_IP");
        }
        result.gasEstimate = gasBefore - gasleft();
    }

    function Curve56QuoteExactInputSingle(
        CurveQuoteExactInputSingleParameters memory parameters
    ) internal view returns (QuoteExactResult memory result) {
        result.amountToPay = parameters.amountIn;
        uint256 gasBefore = gasleft();
        if (parameters.protocol == Protocols.CURVE6) {
            result.amountOut = ICurveCryptoMetaZap(parameters.poolAddress).get_dy(
                parameters.swapAddress,
                uint256(parameters.tokenInIndex),
                uint256(parameters.tokenOutIndex),
                parameters.amountIn
            );
        } else if (parameters.protocol == Protocols.CURVE5) {
            result.amountOut = ICurvePool(parameters.swapAddress).get_dy_underlying(
                int128(int8(parameters.tokenInIndex)),
                int128(int8(parameters.tokenOutIndex)),
                parameters.amountIn
            );
        } else {
            // CRQ_IP: invalid protocol
            revert("CRQ_IP");
        }
        result.gasEstimate = gasBefore - gasleft();
    }
}

