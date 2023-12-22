// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721A.sol";

contract FluidityBullas is ERC721A {
    address public operator_;

    string public ipfsDir_;

    constructor(
        address _recipient,
        string memory _ipfsDir,
        uint256 _quantity
    ) ERC721A("Fluidity Bullas", "FBULLS") {
        ipfsDir_ = _ipfsDir;
        _mintERC2309(_recipient, _quantity);
    }

    function _baseURI() internal view override returns (string memory) {
        return ipfsDir_;
    }
}

