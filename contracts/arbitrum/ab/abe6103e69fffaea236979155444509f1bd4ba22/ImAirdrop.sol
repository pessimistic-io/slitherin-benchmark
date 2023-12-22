// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IERC20Metadata.sol";

interface ImAirdrop is IERC20Metadata {
    function mint(address recipient, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external ;
}


