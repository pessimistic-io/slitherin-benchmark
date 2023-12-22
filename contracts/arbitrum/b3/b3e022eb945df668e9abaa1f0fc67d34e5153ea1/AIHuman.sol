// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// Imports from OpenZeppelin contracts
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ERC20Snapshot.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./draft-ERC20Permit.sol";
import "./ERC20Votes.sol";
import "./ERC20FlashMint.sol";

/// @title AIHuman Token
/// @notice An ERC20 token with additional functionalities like burnable, snapshot, pausable, permit, votes, and flash mint.
/// @author Bulpara Industries
/// @dev Inherits from OpenZeppelin contracts
/// @custom:security-contact security@aihuman.app
contract AIHuman is
    ERC20,
    ERC20Burnable,
    ERC20Snapshot,
    Ownable,
    Pausable,
    ERC20Permit,
    ERC20Votes,
    ERC20FlashMint
{
    uint256 public immutable MAX_SUPPLY = 1_000_000_000 * 10**18;

    /// @notice Constructor sets initial token supply and assigns it to the deployer
    constructor() ERC20("AIHuman", "AIM") ERC20Permit("AIHuman") {
        _mint(msg.sender, 111000 * 10**decimals());
    }

    /// @notice Creates a new snapshot ID
    /// @dev Can only be called by the contract owner
    function snapshot() public onlyOwner {
        _snapshot();
    }

    /// @notice Pauses all token transfers
    /// @dev Can only be called by the contract owner
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpauses all token transfers
    /// @dev Can only be called by the contract owner
    function unpause() public onlyOwner {
        _unpause();
    }

    /// @notice Mints new tokens to the specified address
    /// @param to Address to receive the newly minted tokens
    /// @param amount Amount of tokens to mint
    /// @dev Can only be called by the contract owner and ensures that the total supply does not exceed the max supply
    function mint(address to, uint256 amount) public onlyOwner {
        require(
            totalSupply() + amount <= MAX_SUPPLY,
            "AIHuman: Max supply exceeded"
        );
        _mint(to, amount);
    }

    /// @notice Hook that is called before any token transfer, including minting and burning
    /// @param from Address of the token sender
    /// @param to Address of the token recipient
    /// @param amount Amount of tokens to be transferred
    /// @dev Overrides the `_beforeTokenTransfer` function in ERC20 and ERC20Snapshot
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Snapshot) whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    /// @notice Hook that is called after any token transfer, including minting and burning
    /// @param from Address of the token sender
    /// @param to Address of the token recipient
    /// @param amount Amount of tokens transferred
    /// @dev Overrides the _afterTokenTransfer function in ERC20 and ERC20Votes
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    /// @notice Hook that is called when tokens are minted
    /// @param to Address to receive the newly minted tokens
    /// @param amount Amount of tokens to mint
    /// @dev Overrides the `_mint` function in ERC20 and ERC20Votes
    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    /// @notice Hook that is called when tokens are burned
    /// @param account Address of the token holder whose tokens are being burned
    /// @param amount Amount of tokens to burn
    /// @dev Overrides the `_burn` function in ERC20 and ERC20Votes
    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}

