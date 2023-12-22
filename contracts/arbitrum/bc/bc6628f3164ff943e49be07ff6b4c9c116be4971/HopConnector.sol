// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";

import "./FixedPoint.sol";
import "./UncheckedMath.sol";
import "./Denominations.sol";
import "./IWrappedNativeToken.sol";

import "./IHopL2AMM.sol";
import "./IHopL1Bridge.sol";

/**
 * @title HopConnector
 * @dev Interfaces with Hop Exchange to bridge tokens
 */
contract HopConnector {
    using SafeERC20 for IERC20;
    using FixedPoint for uint256;
    using UncheckedMath for uint256;
    using Denominations for address;

    // Ethereum mainnet chain ID = 1
    uint256 private constant MAINNET_CHAIN_ID = 1;

    // Görli chain ID = 5
    uint256 private constant GOERLI_CHAIN_ID = 5;

    // Expected data length when bridging from L1 to L2: bridge, deadline, relayer, relayer fee
    uint256 private constant ENCODED_DATA_FROM_L1_TO_L2_LENGTH = 128;

    // Expected data length when bridging from L2 to L1: amm, bonder fee
    uint256 private constant ENCODED_DATA_FROM_L2_TO_L1_LENGTH = 64;

    // Expected data length when bridging from L2 to L2: amm, bonder fee, deadline
    uint256 private constant ENCODED_DATA_FROM_L2_TO_L2_LENGTH = 96;

    // Wrapped native token reference
    address private immutable wrappedNativeToken;

    /**
     * @dev Initializes the HopConnector contract
     * @param _wrappedNativeToken Address of the wrapped native token
     */
    constructor(address _wrappedNativeToken) {
        wrappedNativeToken = _wrappedNativeToken;
    }

    /**
     * @dev It allows receiving native token transfers
     */
    receive() external payable {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @dev Internal function to bridge assets using Hop Exchange
     * @param chainId ID of the destination chain
     * @param token Address of the token to be bridged
     * @param amountIn Amount of tokens to be bridged
     * @param minAmountOut Minimum amount of tokens willing to receive on the destination chain
     * @param recipient Address that will receive the tokens on the destination chain
     * @param data ABI encoded data expected to include different information depending on source and destination chains
     */
    function _bridgeHop(
        uint256 chainId,
        address token,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes memory data
    ) internal {
        bool toL2 = !_isL1(chainId);
        bool fromL1 = _isL1(block.chainid);

        if (fromL1 && toL2) _bridgeFromL1ToL2(chainId, token, amountIn, minAmountOut, recipient, data);
        else if (!fromL1 && toL2) _bridgeFromL2ToL2(chainId, token, amountIn, minAmountOut, recipient, data);
        else if (!fromL1 && !toL2) _bridgeFromL2ToL1(chainId, token, amountIn, minAmountOut, recipient, data);
        else revert('HOP_BRIDGE_OP_NOT_SUPPORTED');
    }

    /**
     * @dev Internal function to bridge assets from L1 to L2
     * @param chainId ID of the destination chain
     * @param token Address of the token to be bridged
     * @param amountIn Amount of tokens to be bridged
     * @param minAmountOut Minimum amount of tokens willing to receive on the destination chain
     * @param recipient Address that will receive the tokens on the destination chain
     * @param data ABI encoded data to include:
     * - bridge: address of the Hop bridge corresponding to the token to be bridged
     * - deadline: deadline to be applied on L2 when swapping the hToken for the token to be bridged
     * - relayer: only used if a 3rd party is relaying the transfer on the user's behalf
     * - relayer fee: only used if a 3rd party is relaying the transfer on the user's behalf
     */
    function _bridgeFromL1ToL2(
        uint256 chainId,
        address token,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes memory data
    ) private {
        require(data.length == ENCODED_DATA_FROM_L1_TO_L2_LENGTH, 'HOP_INVALID_L1_L2_DATA_LENGTH');
        (address hopBridge, uint256 deadline, address relayer, uint256 relayerFee) = abi.decode(
            data,
            (address, uint256, address, uint256)
        );

        require(deadline > block.timestamp, 'HOP_BRIDGE_INVALID_DEADLINE');

        uint256 value = _unwrapOrApproveTokens(hopBridge, token, amountIn);
        IHopL1Bridge(hopBridge).sendToL2{ value: value }(
            chainId,
            recipient,
            amountIn,
            minAmountOut,
            deadline,
            relayer,
            relayerFee
        );
    }

    /**
     * @dev Internal function to bridge assets from L2 to L1
     * @param chainId ID of the destination chain
     * @param token Address of the token to be bridged
     * @param amountIn Amount of tokens to be bridged
     * @param minAmountOut Minimum amount of tokens willing to receive on the destination chain
     * @param recipient Address that will receive the tokens on the destination chain
     * @param data ABI encoded data to include:
     * - amm: address of the Hop AMM corresponding to the token to be bridged
     * - deadline: deadline to be applied on L2 when swapping the token for the hToken to be bridged
     * - bonder fee: must be computed using the Hop SDK or API
     */
    function _bridgeFromL2ToL1(
        uint256 chainId,
        address token,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes memory data
    ) private {
        require(data.length == ENCODED_DATA_FROM_L2_TO_L1_LENGTH, 'HOP_INVALID_L2_L1_DATA_LENGTH');
        (address hopAMM, uint256 bonderFee) = abi.decode(data, (address, uint256));

        uint256 value = _unwrapOrApproveTokens(hopAMM, token, amountIn);
        // No destination min amount nor deadline needed since there is no AMM on L1
        IHopL2AMM(hopAMM).swapAndSend{ value: value }(
            chainId,
            recipient,
            amountIn,
            bonderFee,
            minAmountOut,
            block.timestamp,
            0,
            0
        );
    }

    /**
     * @dev Internal function to bridge assets from L2 to L2
     * @param chainId ID of the destination chain
     * @param token Address of the token to be bridged
     * @param amountIn Amount of tokens to be bridged
     * @param minAmountOut Minimum amount of tokens willing to receive on the destination chain
     * @param recipient Address that will receive the tokens on the destination chain
     * @param data ABI encoded data to include:
     * - amm: address of the Hop AMM corresponding to the token to be bridged
     * - deadline: deadline to be applied on the destination L2 when swapping the hToken for the token to be bridged
     * - bonder fee: must be computed using the Hop SDK or API
     */
    function _bridgeFromL2ToL2(
        uint256 chainId,
        address token,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes memory data
    ) private {
        require(data.length == ENCODED_DATA_FROM_L2_TO_L2_LENGTH, 'HOP_INVALID_L2_L2_DATA_LENGTH');
        (address hopAMM, uint256 bonderFee, uint256 deadline) = abi.decode(data, (address, uint256, uint256));

        require(deadline > block.timestamp, 'HOP_BRIDGE_INVALID_DEADLINE');

        uint256 intermediateMinAmountOut = amountIn - ((amountIn - minAmountOut) / 2);
        IHopL2AMM(hopAMM).swapAndSend{ value: _unwrapOrApproveTokens(hopAMM, token, amountIn) }(
            chainId,
            recipient,
            amountIn,
            bonderFee,
            intermediateMinAmountOut,
            block.timestamp,
            minAmountOut,
            deadline
        );
    }

    /**
     * @dev Unwraps or approves the given amount of tokens depending on the token being bridged
     * @param bridge Address of the bridge component to approve the tokens to
     * @param token Address of the token to be bridged
     * @param amount Amount of tokens to be bridged
     * @return value Value that must be used to perform a bridge op
     */
    function _unwrapOrApproveTokens(address bridge, address token, uint256 amount) private returns (uint256 value) {
        if (token == wrappedNativeToken) {
            value = amount;
            IWrappedNativeToken(token).withdraw(amount);
        } else {
            value = 0;
            IERC20(token).safeApprove(bridge, amount);
        }
    }

    /**
     * @dev Tells if a chain ID refers to L1 or not: currently only Ethereum Mainnet or Goerli
     * @param chainId ID of the chain being queried
     */
    function _isL1(uint256 chainId) private pure returns (bool) {
        return chainId == MAINNET_CHAIN_ID || chainId == GOERLI_CHAIN_ID;
    }
}

