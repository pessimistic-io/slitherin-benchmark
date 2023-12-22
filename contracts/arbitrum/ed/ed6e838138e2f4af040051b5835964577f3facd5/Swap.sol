// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {Commands} from "./Commands.sol";
import {BytesLib} from "./BytesLib.sol";
import {IERC20} from "./IERC20.sol";
import {ISpotStorage} from "./ISpotStorage.sol";
import {ISwap} from "./ISwap.sol";
import {ITrade} from "./ITrade.sol";
import {ISpot} from "./ISpot.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {IUniversalRouter} from "./IUniversalRouter.sol";
import {IPermit2} from "./IPermit2.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {IUniswapV3PoolState} from "./IUniswapV3PoolState.sol";
import {SqrtPriceMath} from "./SqrtPriceMath.sol";

error NoAccess(address desired, address given);
error ZeroAddress();
error ZeroAmount();
error CommandMismatch();
error InputMismatch();

/// @title Swap
/// @author 7811
/// @notice Swap contract for swapping two tokens
contract Swap is ISwap {
    using BytesLib for bytes;

    // Spot contract
    ISpot public spot;
    // Trade contract
    ITrade public trade;
    // Universal Router (routes any erc20, ntfs)
    IUniversalRouter public universalRouter;
    // Permit2
    IPermit2 public permit2;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZE
    //////////////////////////////////////////////////////////////*/

    constructor(ISpot _spot, IUniversalRouter _universalRouter, IPermit2 _permit2) {
        spot = _spot;
        universalRouter = _universalRouter;
        permit2 = _permit2;
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice can be called only by the Trade contract
    modifier onlyTrade() {
        if (msg.sender != address(trade)) revert NoAccess(address(trade), msg.sender);
        _;
    }

    /// @notice can be called only by the `owner` of the Spot contract
    modifier onlyOwner() {
        if (msg.sender != spot.owner()) revert NoAccess(spot.owner(), msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function addStfxTrade(address _trade) external onlyOwner {
        if (_trade == address(0)) revert ZeroAddress();
        trade = ITrade(_trade);
    }

    function addStfxSpot(address _spot) external onlyOwner {
        if (_spot == address(0)) revert ZeroAddress();
        spot = ISpot(_spot);
    }

    function swapUniversalRouter(
        address tokenIn,
        address tokenOut,
        uint160 amountIn,
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline,
        address receiver
    ) external override onlyTrade returns (uint96) {
        uint256 amount;
        for (uint256 i = 0; i < commands.length;) {
            bytes calldata input = inputs[i];
            // the address of the receiver should be spot when opening and trade when closing
            if (address(bytes20(input[12:32])) != receiver) revert InputMismatch();
            // since the route can be through v2 and v3, adding the swap amount for each input should be equal to the total swap amount
            amount += uint256(bytes32(input[32:64]));

            if (commands[i] == bytes1(uint8(Commands.V2_SWAP_EXACT_IN))) {
                address[] calldata path = input.toAddressArray(3);
                // the first address of the path should be tokenIn
                if (path[0] != tokenIn) revert InputMismatch();
                // last address of the path should be the tokenOut
                if (path[path.length - 1] != tokenOut) revert InputMismatch();
            } else if (commands[i] == bytes1(uint8(Commands.V3_SWAP_EXACT_IN))) {
                bytes calldata path = input.toBytes(3);
                // the first address of the path should be tokenIn
                if (address(bytes20(path[:20])) != tokenIn) revert InputMismatch();
                // last address of the path should be the tokenOut
                if (address(bytes20(path[path.length - 20:])) != tokenOut) revert InputMismatch();
            } else {
                // if its not v2 or v3, then revert
                revert CommandMismatch();
            }
            unchecked {
                ++i;
            }
        }
        if (amount != uint256(amountIn)) revert InputMismatch();

        spot.transferToken(tokenIn, amountIn);
        IERC20(tokenIn).approve(address(permit2), amountIn);
        permit2.approve(tokenIn, address(universalRouter), amountIn, type(uint48).max);

        uint96 balanceBeforeSwap = uint96(IERC20(tokenOut).balanceOf(receiver));
        if (deadline > 0) universalRouter.execute(commands, inputs, deadline);
        else universalRouter.execute(commands, inputs);
        uint96 balanceAfterSwap = uint96(IERC20(tokenOut).balanceOf(receiver));
        if ((balanceAfterSwap - balanceBeforeSwap) == 0) revert ZeroAmount();

        return balanceAfterSwap - balanceBeforeSwap;
    }
}

