//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721URIStorage.sol";
import "./AccessControl.sol";
import "./Counters.sol";
import "./Strings.sol";
import "./InterfaceArbiDogsNft.sol";

contract ArbiDogsNft is
    ERC721Enumerable,
    ERC721URIStorage,
    InterfaceArbiDogsNft,
    AccessControl
{
    using Counters for Counters.Counter;
    using Strings for uint256;

    Counters.Counter private tokenIds;

    address public immutable minter;
    string public baseURI;

    /*
     * @dev onlyMinter allows only the minter to mint new tokens
     */
    modifier onlyMinter() {
        require(msg.sender == minter, 'ArbiDogsNft: caller is not the minter');
        _;
    }

    /*
     * @dev Constructs a new ArbiDogsNft
     * @param _minter ArbiDogsMinter address
     * @param _baseURI Base URI
     */
    constructor(
        address _minter,
        string memory _uri
    ) ERC721('ArbiDogs Nft', 'ARBIDOGS') {
        require(_minter != address(0), 'ArbiDogsNft: invalid minter address');

        minter = _minter;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setBaseURI(_uri);
    }

    /*
     * @dev setBaseURI external function to set baseURI by owner
     * @param _uri New URI
     */
    function setBaseURI(string memory _uri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setBaseURI(_uri);
        emit SetBaseURI(_uri);
    }

    /*
     * @dev _setBaseURI internal method to set baseUri
     */
    function _setBaseURI(string memory _uri) internal {
        require(bytes(_uri).length != 0, 'ArbiDogsNft: invalid uri');
        baseURI = _uri;
    }

    /*
     * @dev _baseURI returns baseUri
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    /*
     * @dev mints a new token for 'user'
     * @param user Receiver address
     */
    function mint(address user) external onlyMinter {
        tokenIds.increment();
        uint256 tokenId = tokenIds.current();
        _safeMint(user, tokenId);

        emit Mint(user, tokenId);
    }

    // The following functions are overrides required by Solidity.
    /*
     * @dev override tokenURI method
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    /*
     * @dev override supportsInterface method
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /*
     * @dev override _beforeTokenTransfer method
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /*
     * @dev override _burn method
     */
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }
}

