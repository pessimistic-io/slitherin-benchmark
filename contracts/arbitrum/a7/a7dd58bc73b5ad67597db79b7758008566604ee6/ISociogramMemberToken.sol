// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC20.sol";

interface ISociogramMemberToken is IERC20{
    function totalSupply() external view returns(uint256);
    function mint(address to, uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
    function cap() external view returns(uint256);
    function claimFee() external;
}
