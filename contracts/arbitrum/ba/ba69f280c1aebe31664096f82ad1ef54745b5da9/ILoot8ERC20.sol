// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ILoot8ERC20 {
    
    event MinterAdded(address _minter);
    event MinterRemoved(address _minter);
    
    function mint(address account_, uint256 amount_) external;
    function decimals() external view returns (uint8);
    function addMinter(address _minter) external;
    function removeMinter(address _minter) external;
}
