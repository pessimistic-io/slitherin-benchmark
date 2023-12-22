// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./StarState.sol";
import "./Base64.sol";

struct StarWhitelist {
    address addr;
    uint256 numMints;
}

contract Star is StarState {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter internal tokenIdCounter;
    using StringsUpgradeable for uint256;
    event StarMinted(uint256 indexed tokenId, address indexed owner);

    mapping(address => uint256) public whitelistMintCountsRemaining;
    string private _baseURIString;

    function initialize() public initializer {
        __StarState_init();
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseURIString;
    }

    function _placeholderURI() internal pure returns (string memory) {
        return
            "https://shdw-drive.genesysgo.net/ACUoeM2ZfyFioyfdBwn9wKFvELaJdo71Yc3mCMmbsFHZ/star_placeholder.jpg";
    }

    function pause() public onlyAdminOrOwner {
        _pause();
    }

    function unpause() public onlyAdminOrOwner {
        _unpause();
    }

    function allocateWhitelistMint(
        StarWhitelist[] memory _whitelists
    ) public onlyAdminOrOwner {
        for (uint256 i = 0; i < _whitelists.length; i++) {
            whitelistMintCountsRemaining[_whitelists[i].addr] = _whitelists[i]
                .numMints;
        }
    }

    function whitelistMint(
        uint256 _count
    ) external whenNotPaused returns (uint256, uint256) {
        require(_count > 0, "Invalid mint count");
        require(
            whitelistMintCountsRemaining[msg.sender] >= _count,
            "You cannot mint this many Stars"
        );

        uint256 firstMintedId = tokenIdCounter.current() + 1;

        for (uint256 i = 0; i < _count; i++) {
            tokenIdCounter.increment();

            _safeMint(msg.sender, tokenIdCounter.current());
            emit StarMinted(tokenIdCounter.current(), msg.sender);
        }

        whitelistMintCountsRemaining[msg.sender] -= _count;
        return (firstMintedId, _count);
    }

    function setBaseURI(string calldata _newBaseURI) external onlyAdminOrOwner {
        _baseURIString = _newBaseURI;
    }

    function getBaseURI() public view returns (string memory) {
        return _baseURIString;
    }

    function totalSupply() public view returns (uint256) {
        return tokenIdCounter.current();
    }

    // The following functions are overrides required by Solidity.

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        uint256 timestampRaw = getStarStoryTimeStamp(tokenId);
        string memory timestamp = timestampRaw.toString();

        // Id baseURI is set, redirect to unique json file per token
        if (bytes(baseURI).length > 0 && bytes(timestamp).length > 0 && timestampRaw > 0) {
            return string(abi.encodePacked(baseURI, timestamp, '/', tokenId.toString()));
        }

        // compose a placeholder json
        bytes memory dataURI = abi.encodePacked(
            "{",
            '"name": "Star ',
            unicode"★",
            tokenId.toString(),
            '",',
            '"tokenId": ',
            tokenId.toString(),
            ",",
            '"image": "',
            _placeholderURI(),
            '",',
            '"description": "This Star is pristine and untouched. It needs to join the Story to acquire its unique metadata. Find out more on our website: https://www.imstarving.lol",',
            '"attributes": [ {"trait_type": "Type", "value": "Virgin" } ],',
            '"seller_fee_basis_points" : 1000,',
            '"fee_recipient": "0x2A5d8898fa662D5aa1E44390016483212f150075"'
            "}"
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(dataURI)
                )
            );
    }

    function _burn(uint256 tokenId) internal override {
        super._burn(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

