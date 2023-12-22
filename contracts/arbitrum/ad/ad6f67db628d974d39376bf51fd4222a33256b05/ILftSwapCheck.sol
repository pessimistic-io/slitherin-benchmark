pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT
interface ILftSwapCheck {

    function checkPermissions(address _userAddress) external view returns (bool);
    function checkRemove() external returns(bool);
    function UpdateCheckAddress() external returns(bool);
    function UpdateWAddress() external returns(bool);

}
