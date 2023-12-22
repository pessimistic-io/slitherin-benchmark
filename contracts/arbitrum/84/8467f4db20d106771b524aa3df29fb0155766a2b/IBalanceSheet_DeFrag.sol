// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice DeFrag.fi Balance Sheet Interface 
/// @dev For checking ownership of loaned out assets.

interface IBalanceSheet {

    function isExistingUser(address _userAddress) external view returns (bool);
    
    function getTokenIds(address _userAddress) external view returns (uint256[] memory tokenIds);

}
