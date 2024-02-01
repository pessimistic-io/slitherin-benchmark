// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ERC721Enumerable.sol";

contract TheSevensDerivative is ERC721Enumerable, Ownable {
    event IsBurnEnabledChanged(bool newIsBurnEnabled);
    event BaseURIChanged(string newBaseURI);

    uint256 public nextTokenId = 1;
    bool public isBurnEnabled;

    string public baseURI = "https://outkast.world/sevens/metadata/derivative/";

    constructor() ERC721("The Sevens Official Derivative Collection", "SEVENS-DC") {}

    function setIsBurnEnabled(bool _isBurnEnabled) external onlyOwner {
        isBurnEnabled = _isBurnEnabled;
        emit IsBurnEnabledChanged(_isBurnEnabled);
    }

    function setBaseURI(string calldata newbaseURI) external onlyOwner {
        baseURI = newbaseURI;
        emit BaseURIChanged(newbaseURI);
    }

    function mintTokens(address recipient, uint256 count) external onlyOwner {
        require(recipient != address(0), "TheSevensDC: zero address");

        // Gas optimization
        uint256 _nextTokenId = nextTokenId;

        require(count > 0, "TheSevensDC: invalid count");

        for (uint256 ind = 0; ind < count; ind++) {
            _safeMint(recipient, _nextTokenId + ind);
        }
        nextTokenId += count;
    }

    function burn(uint256 tokenId) external {
        require(isBurnEnabled, "TheSevensDC: burning disabled");
        require(_isApprovedOrOwner(msg.sender, tokenId), "TheSevensDC: burn caller is not owner nor approved");
        _burn(tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
