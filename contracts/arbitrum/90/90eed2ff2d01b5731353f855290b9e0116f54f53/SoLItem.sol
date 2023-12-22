//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./SoLItemContracts.sol";

contract SoLItem is Initializable, SoLItemContracts {

    function initialize() external initializer {
        SoLItemContracts.__SoLItemContracts_init();
    }

    function mint(
        address _to,
        uint256 _id,
        uint256 _amount)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    {
        _mint(_to, _id, _amount, "");
    }
}
