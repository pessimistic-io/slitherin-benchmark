//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./BadgezContracts.sol";

contract Badgez is Initializable, BadgezContracts {

    function initialize() external initializer {
        BadgezContracts.__BadgezContracts_init();
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data)
    internal
    override
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        require(isAdmin(msg.sender) || isOwner(), "Badgez: Only admin or owner can transfer Badgez");
    }

    function mintIfNeeded(
        address _to,
        uint256 _id)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    tokenIdExists(_id)
    {
        if(balanceOf(_to, _id) > 0) {
            return;
        }

        _mint(_to, _id, 1, "");
    }
}
