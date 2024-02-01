// @@@@@@@@@@@@@@@@@@@@@@***@@@@@@@***#@@@@@@@@@@@@@***@@@@@@@***@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@***@@@@@@@***#@@@@@@@@@@@@@***@@@@@@@***@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@///@@@@@@@///%@@@@@@@@@@@@@///@@@@@@@///@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@///@@@@@@@///%@@@@@@@@@@@@@///@@@@@@@///@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@..........///@@@@//////////@@@@@@//////////@@@@///.......@@@@@@@@@@@
// @@@@@@@@@@@@..........///@@@@//////////@@@@@@//////////@@@@///.......@@@@@@@@@@@
// @@@@@@@@@..........//////////////////////////////////////////////.......@@@@@@@@
// @@@@@*.............///(((///////((((/////////////(((///////(((///..........@@@@@
// @@@@@*.........((((///***///////***//////////////***///////***///..........@@@@@
// @@@@@*.........((((///***///////***//////////////***///////***///..........@@@@@
// @@@@@*......(((....//////////////////////////////////////////////((((...@@@@@@@@
// @@@@@*......(((.......////////////////////////////////////////(((((((@@@@@@@@@@@
// @@@@@*.........((((......,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,///(((..........@@@@@
// @@@@@*.........((((......,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,///(((..........@@@@@
// @@@@@@@@@......((((......,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,///..........@@@@@@@@
// @@@@@@@@@@@@..........///,,,,,,,&&&&&&&&&&&&&,,,,&&&&&&&&&&&&&.......@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@///,,,,,,,&&&#(((&&&,,,,,,,&&&(((&&&&///@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@///,,,,,,,&&&#(((&&&,,,,,,,&&&(((&&&&///@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@///,,,,,,,&&&&&&&&&&,,,,,,,&&&&&&&&&&///@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@///,,,,,,,,,,(&&&,,,,,,,,,,,,,&&&,,,,///@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@///,,,,,,,,,,,,,,,,,,,,&&&&&&&,,,,,,,///@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@///,,,,,,,,,,,,,,,,,,,,&&&&&&&,,,,,,,///@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@///////,,,,,,,,,,,,,,,,,,,,,,,,,,///////@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@@@@///////,,,,,,,&&&,,,&&&&,,,&&&////@@@@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@@@@////,,,,,,,,,,,,,&&&,,,,&&&,,,////@@@@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@@@@////,,,,,,,,,,,,,&&&,,,,&&&,,,////@@@@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@@@@////,,,,,,,,,,,,,,,,,,,,,,,,,,////@@@@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@@@@////,,,///*,,,,,,,,,,,,,,,,,,,////@@@@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@@@@////,,,,,,*///////////////////@@@@@@@@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@@@@////,,,,,,*///////////////////@@@@@@@@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@@@@////,,,,,,,,,,///@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@@@@////,,,,,,,,,,///@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

//
// ForgottenPunks: SoulPunks
//
// Website: https://forgottenpunks.wtf
// Twitter: https://twitter.com/forgottenpunk
//
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721Burnable.sol";
import "./ERC1155Burnable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

contract SoulPunks is
    ERC721,
    ERC721Enumerable,
    ERC721Burnable,
    Ownable,
    ReentrancyGuard
{
    address public forgottenSpellsAddress;
    uint256 public summonSoulTokenId = 0;

    mapping(uint256 => uint256) public soulIdToSummonerId;
    mapping(uint256 => bool) public summonerIdHasSummoned;

    string private _baseTokenURI;

    bool public mintEnabled = false;
    uint256 public constant MAX_SUPPLY = 666; // TODO

    event SoulSummoned(address tokenContract, uint256 tokenId, uint256 soulId);

    constructor(
        address _forgottenSpellsAddress,
        uint256 _summonSoulTokenId,
        string memory _baseURI
    ) ERC721("SoulPunks", "SoulPunks") {
        forgottenSpellsAddress = _forgottenSpellsAddress;
        summonSoulTokenId = _summonSoulTokenId;
        setBaseURI(_baseURI);
    }

    function baseURI() public view returns (string memory) {
        return _baseTokenURI;
    }

    // You must own a wizard to perform the spell
    function mint(address _tokenContract, uint256 _tokenId)
        public
        nonReentrant
    {
        require(mintEnabled, "MINT_CLOSED");
        require(totalSupply() < MAX_SUPPLY, "SOLD_OUT");
        require(!summonerIdHasSummoned[_tokenId], "WIZARD_USED");
        require(
            IERC721(_tokenContract).ownerOf(_tokenId) == _msgSender(),
            "NOT_OWNER"
        );
        require(
            IERC1155(forgottenSpellsAddress).balanceOf(
                _msgSender(),
                summonSoulTokenId
            ) > 0,
            "NO_SUMMONING_CIRCLES"
        );

        // Burn the Spell
        ERC1155Burnable(forgottenSpellsAddress).burn(
            _msgSender(),
            summonSoulTokenId,
            1
        );

        // Mint the Soul
        uint256 newSoulId = totalSupply();
        _safeMint(_msgSender(), newSoulId);

        // Summoned by
        soulIdToSummonerId[newSoulId] = _tokenId;
        summonerIdHasSummoned[_tokenId] = true;

        emit SoulSummoned(_tokenContract, _tokenId, newSoulId);
    }

    function tokensOfOwner(address _owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = tokenOfOwnerByIndex(_owner, index);
            }
            return result;
        }
    }

    function withdraw() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // Only contract owner shall pass
    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        _baseTokenURI = _newBaseURI;
    }

    function setMintEnabled(bool _newMintEnabled) public onlyOwner {
        mintEnabled = _newMintEnabled;
    }

    function setForgottenSpellsAddress(address _forgottenSpellsAddress)
        public
        onlyOwner
    {
        forgottenSpellsAddress = _forgottenSpellsAddress;
    }

    function setSummonSoulTokenId(uint256 _summonSoulTokenId) public onlyOwner {
        summonSoulTokenId = _summonSoulTokenId;
    }
}

