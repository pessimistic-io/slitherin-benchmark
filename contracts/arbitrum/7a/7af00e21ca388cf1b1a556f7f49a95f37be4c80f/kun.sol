// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./AccessControl.sol";
import "./Pausable.sol";
// import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./ERC721Royalty.sol";
// import "./ERC721A.sol";
import "./ERC721A.sol";
import "./ERC2981.sol";
import "./ERC721AQueryable.sol";

contract kun is AccessControl, Pausable, ERC2981, ERC721A, ERC721AQueryable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    string private _baseTokenURI;

    struct Character {
        uint256 quality;
        uint256 level;
        uint256 score;
    }

    mapping(uint256 => Character) private _characters;

    event BaseURIUpdated(string previousBaseURI, string newBaseURI);

    constructor() ERC721A("MYTHICAL ANIMALS", "MA") {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(MINTER_ROLE, _msgSender());
    }

    function supportsInterface(
        bytes4 interfaceId
    )
    public
    view
    override(AccessControl, ERC2981, ERC721A, IERC721A)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function characters(
        uint256 tokenId
    ) external view returns (uint256 quality, uint256 level, uint256 score) {
        require(_exists(tokenId), "Token does not exist");

        Character memory character = _characters[tokenId];
        return (character.quality, character.level, character.score);
    }

    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    function baseURI() public view returns (string memory) {
        return _baseURI();
    }

    function setBaseURI(
        string memory newBaseURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        string memory previousBaseURI = _baseTokenURI;
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(previousBaseURI, newBaseURI);
    }

    function setDefaultRoyalty(
        address recipient,
        uint96 fraction
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDefaultRoyalty(recipient, fraction);
    }

    function deleteDefaultRoyalty() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _deleteDefaultRoyalty();
    }

    function setTokenRoyalty(
        uint256 tokenId,
        address recipient,
        uint96 fraction
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTokenRoyalty(tokenId, recipient, fraction);
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function mint(address to, uint256 quantity, uint256 id) external {
        require(to != address(0), "ERC721: mint to the zero address");
        uint256 start = _nextTokenId();
        uint256 end = start + quantity;
        for (uint256 i = start; i < end; i++) {
            Character storage character = _characters[i];
            character.quality = id;
        }
        _safeMint(to, quantity);
    }
}

