// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ERC20.sol";

interface IMuchoToken is IERC20Metadata {
    function mint(address recipient, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external ;
}


