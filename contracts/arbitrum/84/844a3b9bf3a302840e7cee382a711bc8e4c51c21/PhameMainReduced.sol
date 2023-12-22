pragma solidity ^0.4.24;

interface ERC721 /* is ERC165 */ {
    function ownerOf(uint256 _tokenId) external view returns (address);
}

/// @title Compliance with ERC-721 for Citadel
/// @dev This implementation assumes:
///  - A fixed supply of NFTs, cannot mint or burn
///  - ids are numbered sequentially starting at 1.
///  - NFTs are initially assigned to this contract
///  - This contract does not externally call its own functions
/// @author dsi (https://twitter.com/CiziaZyke777) inspired by : William Entriken (https://phor.net)
contract Phame is ERC721 {

    uint256 private constant TOTAL_SUPPLY = 7745; // square 1 to square 7745

    mapping (uint256 => address) private _tokenOwnerWithSubstitutions;

    modifier mustBeValidToken(uint256 _tokenId) {
        require(_tokenId >= 1 && _tokenId <= TOTAL_SUPPLY);
        _;
    }

    /// @notice Find the owner of an NFT
    /// @dev NFTs assigned to zero address are considered invalid, and queries
    ///  about them do throw.
    /// @param _tokenId The identifier for an NFT
    /// @return The address of the owner of the NFT
    function ownerOf(uint256 _tokenId)
        external
        view
        mustBeValidToken(_tokenId)
        returns (address _owner)
    {
        _owner = _tokenOwnerWithSubstitutions[_tokenId];
        // Do owner address substitution
        if (_owner == address(0)) {
            _owner = address(this);
        }
    }
}
