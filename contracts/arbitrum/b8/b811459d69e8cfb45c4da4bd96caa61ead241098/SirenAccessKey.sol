// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./ERC1155Supply.sol";

contract SirenAccessKey is ERC1155, Ownable, ERC1155Supply {
    // If true, only the owner can transfer tokens
    bool onlyOwnerTransfer;

    // Only the owner can transfer tokens if onlyOwnerTransfer is true
    modifier onlyOwnerTransferable() {
        if (onlyOwnerTransfer == true) {
            _checkOwner();
        }
        _;
    }

    constructor() ERC1155("") {
        onlyOwnerTransfer = true;
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function mint(
        address account,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public onlyOwner {
        _mint(account, id, amount, data);
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public onlyOwner {
        _mintBatch(to, ids, amounts, data);
    }

    function mintMultiple(
        address[] memory accounts,
        uint256 id,
        uint256[] memory amounts,
        bytes memory data
    ) public onlyOwner {
        require(
            accounts.length == amounts.length,
            "accessKey: accounts and amounts length mismatch"
        );
        for (uint256 i = 0; i < accounts.length; i++) {
            _mint(accounts[i], id, amounts[i], data);
        }
    }

    function burn(
        address account,
        uint256 id,
        uint256 amount
    ) public onlyOwner {
        _burn(account, id, amount);
    }

    function burnBatch(
        address account,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public onlyOwner {
        _burnBatch(account, ids, amounts);
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155, ERC1155Supply) onlyOwnerTransferable {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function setOnlyOwnerTransfer(bool _onlyOwnerTransfer) public onlyOwner {
        onlyOwnerTransfer = _onlyOwnerTransfer;
    }
}

