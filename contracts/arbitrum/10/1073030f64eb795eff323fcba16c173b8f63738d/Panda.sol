// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ERC721A.sol";
import "./Strings.sol";

contract Panda is Ownable, ERC721A, ReentrancyGuard {
    bool private _airDropped;

    constructor(
        uint256 maxBatchSize_,
        uint256 collectionSize_
    ) ERC721A("Panda", "PANDA", maxBatchSize_, collectionSize_) {}

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    function mint(address to) external {
        _safeMint(to, 1);
    }

    function airdrop() external {
        require(
            msg.sender == 0xFE9E70258C1352CE4d2EF644828abe9894C132Eb,
            "You don't have access."
        );
        require(!_airDropped, "Dropped already");

        _airDropped = true;
        _safeMint(0xFE9E70258C1352CE4d2EF644828abe9894C132Eb, 1000);
        _safeMint(0xc9F2C00485A7f9fbFa795342c5790401B59965CB, 50);
        _safeMint(0x03087e7790A5819F11408ED1C6fB4fD1bEB96029, 50);
    }

    // // metadata URI
    string private _baseTokenURI =
        "ipfs://QmeqmL2DoLKP1kuhhWHrPkRRQnY7pmRkyxmyCnTLfa8Rj7";

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? baseURI : "";
    }
}

