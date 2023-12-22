// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

/// @title ITokenMintInternal
/// @dev Interface containing all errors and events used in the Token facet contract
interface ITokenInternal {
    /// @notice thrown when attempting to transfer tokens and the from address is neither
    /// the zero-address, nor the contract address, or the to address is not the zero address
    error NonTransferable();

    /// @notice thrown when an addrss not contained in mintingContracts attempts to mint or burn
    /// tokens
    error NotMintingContract();

    /// @notice emitted when a new distributionFractionBP value is set
    /// @param distributionFractionBP the new distributionFractionBP value
    event DistributionFractionSet(uint32 distributionFractionBP);

    /// @notice emitted when an account is added to mintingContracts
    /// @param account address of account
    event MintingContractAdded(address account);

    /// @notice emitted when an account is removed from mintingContracts
    /// @param account address of account
    event MintingContractRemoved(address account);
}

