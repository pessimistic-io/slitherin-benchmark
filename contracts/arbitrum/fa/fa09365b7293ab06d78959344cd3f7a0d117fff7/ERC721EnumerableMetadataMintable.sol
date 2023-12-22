//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import "./ERC721Enumerable.sol";

contract ERC721EnumerableMetadataMintable is ERC721Enumerable {
    error OnlyMinterAccess();

    address internal _minter;
    string internal _baseTokenURI;
    string internal _contractURI;

    constructor(
        string memory name_,
        string memory symbol_,
        address minter_,
        string memory baseTokenURI_,
        string memory contractURI_
    ) ERC721(name_, symbol_) {
        _minter = minter_;
        _baseTokenURI = baseTokenURI_;
        _contractURI = contractURI_;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    modifier onlyMinterAccess() {
        if (msg.sender != _minter) {
            revert OnlyMinterAccess();
        }
        _;
    }

    function mint(address _to, uint256 _tokenId) external onlyMinterAccess {
        _mint(_to, _tokenId);
    }
}

