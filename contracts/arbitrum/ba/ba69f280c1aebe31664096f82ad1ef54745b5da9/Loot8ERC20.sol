// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./ILoot8ERC20.sol";

import "./ERC20PermitUpgradeable.sol";

contract Loot8ERC20 is ILoot8ERC20, ERC20PermitUpgradeable, DAOAccessControlled {

    // Set of addresses(EOAs or Contracts) that are allowed 
    // to perform the minting operation on this contract
    mapping(address => bool) public isMinter;

    function initialize(address _authority) public initializer {
        ERC20Upgradeable.__ERC20_init("LOOT8 Token", "LOOT-8");
        ERC20PermitUpgradeable.__ERC20Permit_init("LOOT8 Token");
        DAOAccessControlled._setAuthority(_authority); 
    }

    function decimals() public view override(ILoot8ERC20, ERC20Upgradeable) returns (uint8) {
        return ERC20Upgradeable.decimals();
    }

    function addMinter(address _minter) external onlyGovernor {
        isMinter[_minter] = true;
        emit MinterAdded(_minter);
    }

    function removeMinter(address _minter) external onlyGovernor {
        delete isMinter[_minter];
        emit MinterRemoved(_minter);
    }

    function mint(address _account, uint256 _amount) external {
        require(isMinter[_msgSender()], "UNAUTHORIZED");
        _mint(_account, _amount);
    }
    
    function _msgSender() internal view virtual override(ContextUpgradeable, DAOAccessControlled) returns (address _sender) {
        return DAOAccessControlled._msgSender();
    }

    function _msgData() internal view virtual override(ContextUpgradeable, DAOAccessControlled) returns (bytes calldata) {
        return DAOAccessControlled._msgData();
    }
}
