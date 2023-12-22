// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IERC20Metadata.sol";

interface IMintableERC20 is IERC20Metadata{
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
    function isMinter(address account) external returns(bool);
    function setMinter(address _minter, bool _active) external;
}

