//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./CountersUpgradeable.sol";
import "./Initializable.sol";
import "./ERC721URIStorageUpgradeable.sol";
import { Base64 } from "./Base64.sol";
import "./AdminableUpgradeable.sol";
import "./TCTypes.sol";
 
contract TreasureChest is Initializable, AdminableUpgradeable, ERC721URIStorageUpgradeable {

    using CountersUpgradeable for CountersUpgradeable.Counter;
    using StringsUpgradeable for uint256;
    using StringsUpgradeable for uint8;

    CountersUpgradeable.Counter internal tokenIdCounter;

    mapping(address => uint256) public whitelistMintCountsRemaining;
    mapping(address => bool) public isAddressAbleToUpdate;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    uint256 public constant MAX_CHESTS = 10000;
    string imageURL;

    function initialize(string memory url) public initializer {
        __Adminable_init();
        __ERC721URIStorage_init();
        __ERC721_init("Treasure Chest", "TC");
        imageURL = url;
    }

    function whitelistMint(uint256 _count) external whenNotPaused returns (uint256, uint256) {
        require(_count > 0, "Invalid mint count");
        require(tokenIdCounter.current() + _count <= MAX_CHESTS, "All Treasure Chests have been minted");
        require(whitelistMintCountsRemaining[msg.sender] >= _count, "You cannot mint this many Treasure Chests");

        uint256 firstMintedId = tokenIdCounter.current();
        for (uint256 i = 0; i < _count; i++) {
            tokenIdCounter.increment();
            _safeMint(msg.sender, tokenIdCounter.current());
        }
        whitelistMintCountsRemaining[msg.sender] -= _count;
                return (firstMintedId, _count);

    }

    function allocateWhitelistMint(TCTypes.TCWhitelist[] memory _whitelists) public onlyAdminOrOwner {
        for(uint256 i = 0; i < _whitelists.length; i++) {
            whitelistMintCountsRemaining[_whitelists[i].addr] = _whitelists[i].numMints;
        }
    }

    function adminSafeTransferFrom(address _from, address _to, uint256 _tokenId) external onlyAdminOrOwner whenNotPaused {
        _transfer(_from, _to, _tokenId);
    }

    function setimageURL(string calldata _newPlaceHolder) external onlyAdminOrOwner {
        imageURL = _newPlaceHolder;
    }

    function getimageURL() public view returns (string memory) {
        return imageURL;
    }

    function setAddressAbleToUpdate(address _address, bool _isAble) external onlyAdminOrOwner {
        isAddressAbleToUpdate[_address] = _isAble;
    }

    function getIsAddressAbleToUpdate(address _address) public view returns (bool) {
        return isAddressAbleToUpdate[_address];
    }

    function getYesOrNo(bool isYes) internal pure returns (string memory) {
        if(isYes) {
            return "Yes";
        }
        return "No";
    }

    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        require(_exists(_tokenId), "token does not exist");

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{',
                            '"name": "Treasure Chest #', _tokenId.toString(),
                            '", "tokenId": ', _tokenId.toString(),
                            ', "image": ', '"', imageURL,
                            '", "description": "Chest of hold, I pursue not gold, but tools to enrich my journeys sold.",',
                            '"seller_fee_basis_points" : 1000,',
                            '"fee_recipient": "0x2A5d8898fa662D5aa1E44390016483212f150075"'
                        '}'
                    )
                )
            )
        );

        string memory finalTokenUri = string(abi.encodePacked("data:application/json;base64,", json));
        console.log("\n--------------------");
        console.log(finalTokenUri);
        console.log("--------------------\n");
        return finalTokenUri;
    }

    function totalSupply() external view returns(uint256) {
        return tokenIdCounter.current();
    }

}
