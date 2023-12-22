// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
// Import this file to use console.log
interface IAntiBot {
    function onBeforeTokenTransfer(address sender, address recipient, uint256 amount) external;
    function unBlackList(address _token, address[] memory _black) external;
    function addBlackList(address _token, address[] memory _black) external;
    function tokenAdmin(address user) external ;
}
 
