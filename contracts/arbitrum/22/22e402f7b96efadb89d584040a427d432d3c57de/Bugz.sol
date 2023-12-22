//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./BugzContracts.sol";

contract Bugz is Initializable, BugzContracts {

    function initialize() external initializer {
        BugzContracts.__BugzContracts_init();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);

        require(isAdmin(msg.sender) || isOwner(), "Bugz: Only admin or owner can transfer $BUGZ");
    }

    function mint(
        address _to,
        uint256 _amount)
    external
    override
    onlyAdminOrOwner
    {
        _mint(_to, _amount);
    }

    function burn(
        address _from,
        uint256 _amount)
    external
    override
    onlyAdminOrOwner
    {
        _burn(_from, _amount);
    }
}
