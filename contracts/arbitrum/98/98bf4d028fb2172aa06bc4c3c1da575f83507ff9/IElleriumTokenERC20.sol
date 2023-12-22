pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

// Interface for $ELLERIUM.
contract IElleriumTokenERC20 {
    function mint(address _recipient, uint256 _amount) public {}
    function SetBlacklistedAddress(address[] memory _addresses, bool _blacklisted) public {}
}
