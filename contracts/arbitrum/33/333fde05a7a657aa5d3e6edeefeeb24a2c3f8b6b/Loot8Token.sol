// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./ILoot8Token.sol";
import "./DAOAccessControlled.sol";

import "./ERC20.sol";

contract Loot8Token is ILoot8Token, ERC20, DAOAccessControlled {

    constructor(
        address _authority
    )   ERC20("LOOT8 Loyalty Points Token", "LOOT8")
    {
        DAOAccessControlled._setAuthority(_authority);        
    }

    function decimals() public view override(ILoot8Token, ERC20) returns (uint8) {
        return ERC20.decimals();
    }

    function mint(address account_, uint256 amount_) external onlyDispatcher {
        _mint(account_, amount_);
    }
    
    function _msgSender() internal view virtual override(Context, DAOAccessControlled) returns (address sender) {
        return DAOAccessControlled._msgSender();
    }

    function _msgData() internal view virtual override(Context, DAOAccessControlled) returns (bytes calldata) {
        return DAOAccessControlled._msgData();
    }
}
