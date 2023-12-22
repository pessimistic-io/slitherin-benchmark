// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./ERC1155Supply.sol";

contract OgInBorderland is ERC1155, Ownable, ERC1155Supply {
    uint256 public constant OG_TOKEN = 0;
    uint256 public constant MAX_TOTAL_SUPPLY = 26;

    constructor() ERC1155("https://ipfs.io/ipfs/QmZYAQqnNfViHympxHNoTQQJ916aKBhrvGaadBPNLu1UgQ/{id}.json") {}

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function airdrop(address[] calldata ogs) external onlyOwner {
        require(
            ogs.length <= MAX_TOTAL_SUPPLY &&
                ogs.length + totalSupply(OG_TOKEN) <= MAX_TOTAL_SUPPLY,
            "Cannot airdrop more thant total supply"
        );
        for (uint256 i = 0; i < ogs.length; i++) {
            _mint(ogs[i], OG_TOKEN, 1, "");
        }
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155, ERC1155Supply) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}

