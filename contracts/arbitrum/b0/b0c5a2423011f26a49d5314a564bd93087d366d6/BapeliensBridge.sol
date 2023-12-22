// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC721.sol";

/// @title Bapeliens contract
contract BapeliensBridge is Pausable, Ownable {
    error InvalidBapeliensContract();
    error InvalidTokenArrayLength();
    error NotTokenOwner();
    error TokenNotInContract();
    error NoTokenOwner();

    /**
     * Events
     */

    /// @notice gets emitted when a larvae has been bridged
    event BapelienBridged(address owner, uint256[] tokenIds);

    /**
     * Public state variables
     */

    IERC721 public bapeliens;
    mapping(uint256 => address) public bridgedOwner;

    /**
     * Constructor
     */

    /// @param bapelienAddress_ Address of the Bapeliens contract
    constructor(address bapelienAddress_) {
        bapeliens = IERC721(bapelienAddress_);
        _pause();
    }

    /**
     * Public functions
     */

    /// @notice Bridge token to Polygon
    /// @param tokenIds TokenIDs to transfer
    function bridge(uint256[] memory tokenIds) public whenNotPaused {
        uint256 length = tokenIds.length;

        if (address(bapeliens) == address(0)) revert InvalidBapeliensContract();
        if (length == 0 || length > 10) revert InvalidTokenArrayLength();

        for (uint256 i = 0; i < length; ) {
            if (bapeliens.ownerOf(tokenIds[i]) != msg.sender) revert NotTokenOwner();
            bridgedOwner[tokenIds[i]] = msg.sender;
            bapeliens.transferFrom(msg.sender, address(this), tokenIds[i]);
            unchecked {
                i++;
            }
        }

        emit BapelienBridged(msg.sender, tokenIds);
    }

    /**
     * Public owner functions
     */

    /// @notice Sets the Bapeliens contract address
    /// @param newBapeliensAddress Bapeliens contract address
    function setBapeliensAddress(address newBapeliensAddress) public onlyOwner {
        bapeliens = IERC721(newBapeliensAddress);
    }

    /// @notice Emergency transfer NFT back to original holder
    /// @param tokenId TokenID to transfer back
    function emergencyReturn(uint256 tokenId) public onlyOwner {
        if (address(bapeliens) == address(0)) revert InvalidBapeliensContract();
        if (bapeliens.ownerOf(tokenId) != address(this)) revert TokenNotInContract();
        if (bridgedOwner[tokenId] == address(0)) revert NoTokenOwner();
        bapeliens.transferFrom(address(this), bridgedOwner[tokenId], tokenId);
    }

    /// @notice Pauses all bridge transactions
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpauses all bridge transactions to allow for normal operation
    function unpause() public onlyOwner {
        _unpause();
    }
}

