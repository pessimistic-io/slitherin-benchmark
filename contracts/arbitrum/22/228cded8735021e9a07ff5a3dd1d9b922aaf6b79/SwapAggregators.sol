// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Pino.sol";
import "./IWETH9.sol";
import "./ISwapAggregators.sol";
import "./SafeERC20.sol";

/// @title Swap Aggregators Proxy contract
/// @author Matin Kaboli
/// @notice Swaps tokens and send the new token to msg.sender
/// @dev This contract uses Permit2
contract SwapAggregators is ISwapAggregators, Pino {
    using SafeERC20 for IERC20;

    address public OInch;
    address public Paraswap;

    /// @notice Sets 1Inch and Paraswap variables and approves some tokens to them
    /// @param _permit2 Permit2 contract address
    /// @param _weth WETH9 contract address
    /// @param _oInch 1Inch contract address
    /// @param _paraswap Paraswap contract address
    constructor(Permit2 _permit2, IWETH9 _weth, address _oInch, address _paraswap) Pino(_permit2, _weth) {
        OInch = _oInch;
        Paraswap = _paraswap;
    }

    /// @notice Swaps using 1Inch protocol
    /// @param _data 1Inch protocol data from API
    function swap1Inch(bytes calldata _data) external payable {
        (bool success,) = OInch.call(_data);

        _require(success, ErrorCodes.FAIELD_TO_SWAP_USING_1INCH);
    }

    /// @notice Swaps using Paraswap protocol
    /// @param _data Paraswap protocol generated data from API
    function swapParaswap(bytes calldata _data) external payable {
        (bool success,) = Paraswap.call(_data);

        _require(success, ErrorCodes.FAIELD_TO_SWAP_USING_PARASWAP);
    }

    /// @notice Swaps using 0x protocol
    /// @param _swapTarget Swap target address, used for sending _data
    /// @param _data 0x protocol generated data from API
    function swap0x(address _swapTarget, bytes calldata _data) external payable {
        (bool success,) = payable(_swapTarget).call(_data);

        _require(success, ErrorCodes.FAIELD_TO_SWAP_USING_0X);
    }

    /// @notice Sets new addresses for 1Inch and Paraswap protocols
    /// @param _oInch Address of the new 1Inch contract
    /// @param _paraswap Address of the new Paraswap contract
    function setDexAddresses(address _oInch, address _paraswap) external onlyOwner {
        OInch = _oInch;
        Paraswap = _paraswap;
    }
}

