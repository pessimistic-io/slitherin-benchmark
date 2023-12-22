// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC721.sol";
import "./Ownable.sol";

/**
 * @title PositionToken
 * @notice This smart contract is called PositionToken and is an ERC721 token that allows for minting and burning of tokens.
 * @notice Ownership of the contract is restricted to the contract owner.
 */
contract PositionToken is ERC721, Ownable {
    /**
     * @notice Constructor for PositionToken.
     * @param name_ The name of the token.
     * @param symbol_ The symbol of the token.
     */
    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

    /**
     * @notice Function to burn a token.
     * @param id The ID of the token to be burned.
     * @return bool Returns true if the token was successfully burned.
     */
    function burn(uint256 id) external onlyOwner returns (bool) {
        _burn(id);
        return true;
    }

    /**
     * @notice Function to mint a token.
     * @param account The address to which the token will be minted.
     * @param id The ID of the token to be minted.
     * @return bool Returns true if the token was successfully minted.
     */
    function mint(address account, uint256 id) external onlyOwner returns (bool) {
        _mint(account, id);
        return true;
    }
}

