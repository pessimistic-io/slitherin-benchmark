// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ITerm, IAgreementManager} from "./ITerm.sol";

import {IERC20} from "./IERC20.sol";

/// @notice Agreement Term requiring token payment.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/ITokenTransfer.sol)
interface ITokenTransfer is ITerm {
    /// @dev Data structure for TokenTransfer properties
    struct TokenTransferData {
        // token contract address
        IERC20 token;
        // payable to
        address to;
        // total amount to transfer, including amount previously transferred
        uint256 amount;
        // payments disallowed in advance of other terms?
        bool restrictedExercise;
        // amount previously transferred
        uint256 priorTransfers;
    }

    error TokenTransfer__RestrictedExercise();
    error TokenTransfer__PriorTransfersTooLarge();

    function getData(IAgreementManager manager, uint256 tokenId) external view returns (TokenTransferData memory);

    function payableAmount(IAgreementManager manager, uint256 tokenId) external view returns (uint256);

    function transfer(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 amount
    ) external;
}

