// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./AccessControl.sol";
import "./BehaviorSafetyMethods.sol";

contract ComponentTreasuryEth is Ownable, AccessControl, BehaviorSafetyMethods {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantTreasuryAccess(address(this), true);
        grantTreasuryAccess(msg.sender, true);
    }

    function treasuryBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function grantTreasuryAccess(address _address, bool _allowed) public onlyOwner {
        if (_allowed) _grantRole(MANAGER_ROLE, _address);
        else _revokeRole(MANAGER_ROLE, _address);
    }

    function deposit() public payable onlyRole(MANAGER_ROLE) {}

    function transferTo(address _target, uint256 _amount) public onlyRole(MANAGER_ROLE) {
        (bool sent, ) = payable(_target).call{value: _amount}("");
        require(sent, "Failed to send Ether");
    }

    receive() external payable {}
}

