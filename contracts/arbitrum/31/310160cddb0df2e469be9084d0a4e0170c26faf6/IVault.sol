// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

import {IERC721Enumerable} from "./IERC721Enumerable.sol";

import {IDefii} from "./IDefii.sol";
import {Status} from "./StatusLogic.sol";

interface IVault is IERC721Enumerable {
    /// @notice Event emitted when vault balance has changed
    /// @param positionId Position id
    /// @param token token address
    /// @param amount token amount
    /// @param increased True if balance increased, False if balance decreased
    /// @dev You can get current balance via `funds(token, positionId)`
    event BalanceChanged(
        uint256 indexed positionId,
        address indexed token,
        uint256 amount,
        bool increased
    );

    /// @notice Event emitted when defii status changed
    /// @param positionId Position id
    /// @param defii Defii address
    /// @param newStatus New status
    event DefiiStatusChanged(
        uint256 indexed positionId,
        address indexed defii,
        Status indexed newStatus
    );

    /// @notice Reverts, for example, if you try twice run enterDefii before processing ended
    /// @param currentStatus - Current defii status
    /// @param wantStatus - Want defii status
    /// @param positionStatus - Position status
    error CantChangeDefiiStatus(
        Status currentStatus,
        Status wantStatus,
        Status positionStatus
    );

    /// @notice Reverts if trying to decrease more balance than there is
    error InsufficientBalance(
        uint256 positionId,
        address token,
        uint256 balance,
        uint256 needed
    );

    /// @notice Reverts if trying to exit with 0% or > 100%
    error WrongExitPercentage(uint256 percentage);

    /// @notice Reverts if position processing in case we can't
    error PositionProcessing();

    /// @notice Reverts if trying use unknown defii
    error UnsupportedDefii(address defii);

    /// @notice Deposits token to vault. If caller don't have position, opens it
    /// @param token Token address.
    /// @param amount Token amount.
    /// @param operatorFeeAmount Fee for operator (offchain service help)
    /// @dev You need to get `operatorFeeAmount` from API or set it to 0, if you don't need operator
    function deposit(
        address token,
        uint256 amount,
        uint256 operatorFeeAmount
    ) external returns (uint256 positionId);

    /// @notice Deposits token to vault. If caller don't have position, opens it
    /// @param token Token address
    /// @param amount Token amount
    /// @param operatorFeeAmount Fee for operator (offchain service help)
    /// @param deadline Permit deadline
    /// @param permitV The V parameter of ERC712 permit sig
    /// @param permitR The R parameter of ERC712 permit sig
    /// @param permitS The S parameter of ERC712 permit sig
    /// @dev You need to get `operatorFeeAmount` from API or set it to 0, if you don't need operator
    function depositWithPermit(
        address token,
        uint256 amount,
        uint256 operatorFeeAmount,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external returns (uint256 positionId);

    /// @notice Deposits token to vault. If caller don't have position, opens it
    /// @param positionId Position id
    /// @param token Token address
    /// @param amount Token amount
    /// @param operatorFeeAmount Fee for operator (offchain service help)
    /// @dev You need to get `operatorFeeAmount` from API or set it to 0, if you don't need operator
    function depositToPosition(
        uint256 positionId,
        address token,
        uint256 amount,
        uint256 operatorFeeAmount
    ) external;

    /// @notice Withdraws token from vault
    /// @param token Token address
    /// @param amount Token amount
    /// @param positionId Position id
    /// @dev Validates, that position not processing, if `token` is `NOTION`
    function withdraw(
        address token,
        uint256 amount,
        uint256 positionId
    ) external;

    /// @notice Enters the defii
    /// @param defii Defii address
    /// @param positionId Position id
    /// @param instructions List with encoded instructions for DEFII
    function enterDefii(
        address defii,
        uint256 positionId,
        IDefii.Instruction[] calldata instructions
    ) external payable;

    /// @notice Callback for DEFII
    /// @param positionId Position id
    /// @param shares Minted shares amount
    /// @dev DEFII should call it after enter
    function enterCallback(uint256 positionId, uint256 shares) external;

    /// @notice Exits from defii
    /// @param defii Defii address
    /// @param positionId Position id
    /// @param instructions List with encoded instructions for DEFII
    function exitDefii(
        address defii,
        uint256 positionId,
        IDefii.Instruction[] calldata instructions
    ) external payable;

    /// @notice Callback for DEFII
    /// @param positionId Position id
    /// @dev DEFII should call it after exit
    function exitCallback(uint256 positionId) external;

    function NOTION() external returns (address);
}

