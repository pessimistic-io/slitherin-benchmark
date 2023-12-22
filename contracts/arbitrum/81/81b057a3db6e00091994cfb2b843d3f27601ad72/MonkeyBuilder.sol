// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;


import "./ERC721Drop.sol";

contract MonkeyBuilder is ERC721Drop {
    IERC20 private _HighMonkeyCoin;
    uint256 private _price = 4200;
    uint256 private _currentTokenId = 1;

    string private _baseTokenURI;

    event NftMinted(address indexed owner, uint256 indexed tokenId);

    constructor(
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _primarySaleRecipient,
        address highMonkeyCoin_,
        string memory baseTokenURI
    )
        ERC721Drop(
            _name,
            _symbol,
            _royaltyRecipient,
            _royaltyBps,
            _primarySaleRecipient
        )
    {
        _HighMonkeyCoin = IERC20(highMonkeyCoin_);
        _baseTokenURI = baseTokenURI;
    }

    function mintNft() public {
        require(_HighMonkeyCoin.balanceOf(msg.sender) >= _price, "Not enough HIGH tokens");
        _HighMonkeyCoin.transferFrom(msg.sender, address(this), _price);

        _safeMint(msg.sender, _currentTokenId);
        emit NftMinted(msg.sender, _currentTokenId);
        _currentTokenId++;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(_baseTokenURI, uintToString(tokenId)));
    }

    function uintToString(uint256 v) private pure returns (string memory str) {
        if (v == 0) {
            return "0";
        }
        uint256 maxlength = 100;
        bytes memory reversed = new bytes(maxlength);
        uint256 i = 0;
        while (v != 0) {
            uint256 remainder = v % 10;
            v = v / 10;
          reversed[i++] = bytes1(uint8(48 + remainder));

        }
        bytes memory s = new bytes(i);
        for (uint256 j = 0; j < i; j++) {
            s[j] = reversed[i - 1 - j];
        }
        str = string(s);
    }
}

