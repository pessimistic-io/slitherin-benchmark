// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./AccessControl.sol";
import "./BehaviorSafetyMethods.sol";

contract ComponentTreasuryErc20 is Ownable, AccessControl, BehaviorSafetyMethods {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    address public addressManagedToken;
    IERC20 public managedToken;

    constructor(address _addressManagedToken) {
        addressManagedToken = _addressManagedToken;
        managedToken = IERC20(_addressManagedToken);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantTreasuryAccess(address(this), true);
        grantTreasuryAccess(msg.sender, true);
    }

    function treasuryBalance() public view returns (uint256) {
        return managedToken.balanceOf(address(this));
    }

    function grantTreasuryAccess(address _address, bool _allowed) public onlyOwner {
        if (_allowed) _grantRole(MANAGER_ROLE, _address);
        else _revokeRole(MANAGER_ROLE, _address);
    }

    function deposit(uint256 _amount) public onlyRole(MANAGER_ROLE) {
        managedToken.transferFrom(msg.sender, address(this), _amount);
    }

    function transferTo(address _target, uint256 _amount) public onlyRole(MANAGER_ROLE) {
        managedToken.transfer(_target, _amount);
    }
}

