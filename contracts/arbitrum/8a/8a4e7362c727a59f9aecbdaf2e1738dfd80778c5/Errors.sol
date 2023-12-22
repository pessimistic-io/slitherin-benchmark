// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/// @dev Thrown upon attempt to transfer tokens between accounts.
error TransferNotAllowed();

/// @dev Thrown upon attempt to mint or burn tokens after supply was frozen.
error SupplyIsFrozen();

/// @dev Thrown upon attempt to enable swapping when supply is not frozen.
error SupplyIsNotFrozen();

/// @dev Thrown when the HYPS balance is not enough to cover the swap of all PreHYPS.
error InsufficientHYPSBalance();

/// @dev Thrown when the HYPS token address is invalid.
error InvalidHYPSAddress();

/// @dev Thrown upon attempt to enable swapping when it is already enabled.
error SwappingIsAlreadyEnabled();

/// @dev Thrown upon attempt to swap tokens when the swapping is not enabled.
error SwappingIsNotAllowed();

/// @dev Thrown upon attempt to mint tokens above the cap.
error TokenSupplyCapExceeded();

/// @dev Thrown upon to swap tokens when the caller has no PreHYPS balance.
error InsufficientPreHYPSBalance();

/// @dev Thrown upon attempt to set the soft cap to a value greater than the hard cap.
error SoftCapExceedsHardCap();

