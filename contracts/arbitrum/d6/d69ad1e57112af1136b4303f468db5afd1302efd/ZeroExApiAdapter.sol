// SPDX-License-Identifier: Apache License
pragma solidity >=0.8.4;

import { CallUtils } from "./BubbleReverts.sol";
import { IZeroExAdapterStructs } from "./IZeroExSwapHandler.sol";

/**
 * @title ZeroExApiAdapter
 * @author Set Protocol
 *
 * Exchange adapter for 0xAPI that returns data for swaps
 */
abstract contract ZeroExApiAdapter is IZeroExAdapterStructs {
    /* ============ State Variables ============ */

    // ETH pseudo-token address used by 0x API.
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Byte size of Uniswap V3 encoded path addresses and pool fees
    uint256 private constant UNISWAP_V3_PATH_ADDRESS_SIZE = 20;
    uint256 private constant UNISWAP_V3_PATH_FEE_SIZE = 3;
    // Minimum byte size of a single hop Uniswap V3 encoded path (token address + fee + token adress)
    uint256 private constant UNISWAP_V3_SINGLE_HOP_PATH_SIZE =
        UNISWAP_V3_PATH_ADDRESS_SIZE + UNISWAP_V3_PATH_FEE_SIZE + UNISWAP_V3_PATH_ADDRESS_SIZE;
    // Byte size of one hop in the Uniswap V3 encoded path (token address + fee)
    uint256 private constant UNISWAP_V3_SINGLE_HOP_OFFSET_SIZE =
        UNISWAP_V3_PATH_ADDRESS_SIZE + UNISWAP_V3_PATH_FEE_SIZE;

    // Address of the deployed ZeroEx contract.
    address public immutable zeroExAddress;
    // Address of the WETH9 contract.
    address public immutable wethAddress;

    // Returns the address to approve source tokens to for trading. This is the TokenTaker address
    address public immutable getSpender;

    /* ============ constructor ============ */

    constructor(address _zeroExAddress, address _wethAddress) {
        zeroExAddress = _zeroExAddress;
        wethAddress = _wethAddress;
        getSpender = _zeroExAddress;
    }

    /* ============ External Getter Functions ============ */

    /**
     * Return 0xAPI calldata which is already generated from 0xAPI
     *
     * @param  _sourceToken              Address of source token to be sold
     * @param  _destinationToken         Address of destination token to buy
     * @param  _destinationAddress       Address that assets should be transferred to
     * @param  _sourceQuantity           Amount of source token to sell
     * @param  _minDestinationQuantity   Min amount of destination token to buy
     * @param  _data                     Arbitrage bytes containing trade call data
     */
    // solhint-disable-next-line code-complexity
    function _validateZeroExPayload(
        address _sourceToken,
        address _destinationToken,
        address _destinationAddress,
        uint256 _sourceQuantity,
        uint256 _minDestinationQuantity,
        bytes memory _data
    ) internal view {
        address inputToken;
        address outputToken;
        address recipient;
        bool supportsRecipient;
        uint256 inputTokenAmount;
        uint256 minOutputTokenAmount;
        require(_data.length >= 4, "Invalid calldata");

        {
            bytes4 selector;
            bytes memory data;

            // solhint-disable-next-line no-inline-assembly
            assembly {
                selector := mload(add(_data, 0x20)) // Load the first 4 bytes
                let dataLength := sub(mload(_data), 4) // Calculate the length of the data
                data := mload(0x40) // Get the free memory pointer
                mstore(0x40, add(data, add(dataLength, 0x20))) // Update the free memory pointer
                mstore(data, dataLength) // Store the length of the data at the beginning of the data memory
                // Copy the data (excluding the selector) to the allocated memory
                mstore(add(data, 0x20), shr(32, mload(add(_data, 0x24))))
            }
            if (selector == 0x415565b0) {
                // transformERC20()
                (inputToken, outputToken, inputTokenAmount, minOutputTokenAmount) = abi.decode(
                    data,
                    (address, address, uint256, uint256)
                );
            } else if (selector == 0xf7fcd384) {
                // sellToLiquidityProvider()
                (inputToken, outputToken, , recipient, inputTokenAmount, minOutputTokenAmount) = abi.decode(
                    data,
                    (address, address, address, address, uint256, uint256)
                );
                supportsRecipient = true;
                if (recipient == address(0)) {
                    recipient = _destinationAddress;
                }
            } else if (selector == 0xd9627aa4) {
                // sellToUniswap()
                address[] memory path;
                (path, inputTokenAmount, minOutputTokenAmount) = abi.decode(data, (address[], uint256, uint256));
                require(path.length > 1, "Uniswap token path too short");
                inputToken = path[0];
                outputToken = path[path.length - 1];
            } else if (selector == 0xafc6728e) {
                // batchFill()
                BatchFillData memory fillData;
                (fillData, minOutputTokenAmount) = abi.decode(data, (BatchFillData, uint256));
                inputToken = fillData.inputToken;
                outputToken = fillData.outputToken;
                inputTokenAmount = fillData.sellAmount;
            } else if (selector == 0x21c184b6) {
                // multiHopFill()
                MultiHopFillData memory fillData;
                (fillData, minOutputTokenAmount) = abi.decode(data, (MultiHopFillData, uint256));
                require(fillData.tokens.length > 1, "Multihop token path too short");
                inputToken = fillData.tokens[0];
                outputToken = fillData.tokens[fillData.tokens.length - 1];
                inputTokenAmount = fillData.sellAmount;
            } else if (selector == 0x6af479b2) {
                // sellTokenForTokenToUniswapV3()
                bytes memory encodedPath;
                (encodedPath, inputTokenAmount, minOutputTokenAmount, recipient) = abi.decode(
                    data,
                    (bytes, uint256, uint256, address)
                );
                supportsRecipient = true;
                if (recipient == address(0)) {
                    recipient = _destinationAddress;
                }
                (inputToken, outputToken) = _decodeTokensFromUniswapV3EncodedPath(encodedPath);
            } else if (selector == 0x803ba26d) {
                // sellTokenForEthToUniswapV3()
                bytes memory encodedPath;
                (encodedPath, inputTokenAmount, minOutputTokenAmount, recipient) = abi.decode(
                    data,
                    (bytes, uint256, uint256, address)
                );
                supportsRecipient = true;
                if (recipient == address(0)) {
                    recipient = _destinationAddress;
                }
                (inputToken, outputToken) = _decodeTokensFromUniswapV3EncodedPath(encodedPath);
                require(outputToken == wethAddress, "Last token must be WETH");
                outputToken = ETH_ADDRESS;
            } else if (selector == 0x3598d8ab) {
                // sellEthForTokenToUniswapV3()
                inputTokenAmount = _sourceQuantity;
                bytes memory encodedPath;
                (encodedPath, minOutputTokenAmount, recipient) = abi.decode(data, (bytes, uint256, address));
                supportsRecipient = true;
                if (recipient == address(0)) {
                    recipient = _destinationAddress;
                }
                (inputToken, outputToken) = _decodeTokensFromUniswapV3EncodedPath(encodedPath);
                require(inputToken == wethAddress, "First token must be WETH");
                inputToken = ETH_ADDRESS;
            } else {
                revert("Unsupported 0xAPI function selector");
            }
        }

        require(inputToken == _sourceToken, "Mismatched input token");
        require(outputToken == _destinationToken, "Mismatched output token");
        require(!supportsRecipient || recipient == _destinationAddress, "Mismatched recipient");
        require(inputTokenAmount == _sourceQuantity, "Mismatched input token quantity");
        require(minOutputTokenAmount >= _minDestinationQuantity, "Mismatched output token quantity");
    }

    // Decode input and output tokens from an arbitrary length encoded Uniswap V3 path
    function _decodeTokensFromUniswapV3EncodedPath(
        bytes memory encodedPath
    ) private pure returns (address inputToken, address outputToken) {
        require(encodedPath.length >= UNISWAP_V3_SINGLE_HOP_PATH_SIZE, "UniswapV3 token path too short");
        // UniswapV3 paths are packed encoded as (address(token0), uint24(fee), address(token1), [...])
        // We want the first and last token.
        uint256 numHops = (encodedPath.length - UNISWAP_V3_PATH_ADDRESS_SIZE) / UNISWAP_V3_SINGLE_HOP_OFFSET_SIZE;
        uint256 lastTokenOffset = numHops * UNISWAP_V3_SINGLE_HOP_OFFSET_SIZE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let p := add(encodedPath, 32)
            inputToken := shr(96, mload(p))
            p := add(p, lastTokenOffset)
            outputToken := shr(96, mload(p))
        }
    }
}

