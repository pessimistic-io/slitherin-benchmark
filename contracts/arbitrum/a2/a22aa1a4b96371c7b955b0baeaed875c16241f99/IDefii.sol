// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";

interface IDefii is IERC20 {
    /// @notice Instruction type
    /// @dev SWAP_BRIDGE is combination of SWAP + BRIDGE instructions.
    /// @dev Data for MIN_LIQUIDITY_DELTA type is just `uint256`
    enum InstructionType {
        SWAP,
        BRIDGE,
        SWAP_BRIDGE,
        REMOTE_CALL,
        MIN_LIQUIDITY_DELTA,
        MIN_TOKENS_DELTA
    }

    /// @notice DEFII type
    enum Type {
        LOCAL,
        REMOTE
    }

    /// @notice DEFII instruction
    struct Instruction {
        InstructionType type_;
        bytes data;
    }

    /// @notice Swap instruction
    /// @dev `routerCalldata` - 1inch router calldata from API
    struct SwapInstruction {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        bytes routerCalldata;
    }

    /// @notice Bridge instruction
    /// @dev `slippage` should be in bps
    struct BridgeInstruction {
        address token;
        uint256 amount;
        uint256 slippage;
        address bridgeAdapter;
        uint256 value;
        bytes bridgeParams;
    }

    /// @notice Swap and bridge instruction. Do swap and bridge all token from swap
    /// @dev `routerCalldata` - 1inch router calldata from API
    /// @dev `slippage` should be in bps
    struct SwapBridgeInstruction {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        bytes routerCalldata;
        address bridgeAdapter;
        uint256 value;
        bytes bridgeParams;
        uint256 slippage;
    }

    struct MinTokensDeltaInstruction {
        address[] tokens;
        uint256[] deltas;
    }

    /// @notice Enters DEFII with predefined logic
    /// @param amount Notion amount for enter
    /// @param positionId Position id (used in callback)
    /// @param instructions List with instructions for enter
    /// @dev Caller should implement `IVault` interface
    function enter(
        uint256 amount,
        uint256 positionId,
        Instruction[] calldata instructions
    ) external payable;

    /// @notice Exits from DEFII with predefined logic
    /// @param shares Defii lp amount to burn
    /// @param positionId Position id (used in callback)
    /// @param instructions List with instructions for enter
    /// @dev Caller should implement `IVault` interface
    function exit(
        uint256 shares,
        uint256 positionId,
        Instruction[] calldata instructions
    ) external payable;

    /// @notice Withdraw liquidity (eg lp tokens) from
    /// @param shares Defii lp amount to burn
    /// @param recipient Address for withdrawal
    /// @param instructions List with instructions
    /// @dev Caller should implement `IVault` interface
    function withdrawLiquidity(
        address recipient,
        uint256 shares,
        Instruction[] calldata instructions
    ) external payable;

    /// @notice DEFII notion (start token)
    /// @return notion address
    // solhint-disable-next-line named-return-values
    function notion() external view returns (address);

    /// @notice DEFII type
    /// @return type Type
    // solhint-disable-next-line named-return-values
    function defiiType() external pure returns (Type);
}

