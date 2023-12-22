// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.5.0;

interface IMintCallback {
    /// @notice Called to `msg.sender` after executing a mint via Lendgine
    /// @dev In the implementation you must pay the speculative tokens owed for the mint.
    /// The caller of this method must be checked to be a Lendgine deployed by the canonical Factory.
    /// @param data Any data passed through by the caller via the Mint call
    function MintCallback(uint256 amount0, bytes calldata data) external;
}

