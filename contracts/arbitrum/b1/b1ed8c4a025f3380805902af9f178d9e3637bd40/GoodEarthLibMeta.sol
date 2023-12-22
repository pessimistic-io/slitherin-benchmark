// SPDX-License-Identifier: None
pragma solidity 0.8.18;

library LibMeta {
    function _msgSender() internal view returns (address sender_) {
        if (msg.sender == address(this)) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            /// @solidity memory-safe-assembly
            assembly {
                sender_ := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            sender_ = msg.sender;
        }
    }

    /**
     * @dev Emitted when an incorrect payment amount is provided.
     * @param amount The provided payment amount
     * @param price The expected payment amount (price)
     */
    error IncorrectPaymentAmount(uint256 amount, uint256 price);

    /**
     * @dev Emitted when an incorrect USD amount is provided.
     * @param price The provided payment amount in 8-decimal USD
     */
    error InvalidUSDPrice(uint256 price);

    /**
     * @dev Emitted when the sender is not a valid spellcaster payment address.
     * @param sender The address of the sender attempting the action
     */
    error SenderNotSpellcasterPayments(address sender);

    /**
     * @dev Emitted when a non-accepted payment type is provided.
     * @param paymentType The provided payment type
     */
    error PaymentTypeNotAccepted(string paymentType);

    error NoActiveBattlePass();
    error BattlePassAlreadyClaimed();
}

