// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ERC20.sol";
import "./AccessControl.sol";

contract PlaceholderConvertibleAmbrosia is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MinterRole");
    bytes32 public constant BURNER_ROLE = keccak256("BurnerRole");

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(address _to, uint256 _amount) public onlyRole(MINTER_ROLE) {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) public onlyRole(BURNER_ROLE) {
        _burn(_from, _amount);
    }

    function adminGrantRole(address _addr, bytes32 _role, bool _grant) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_grant) {
            grantRole(_role, _addr);
        }
        else {
            revokeRole(_role, _addr);
        }
    }
}

