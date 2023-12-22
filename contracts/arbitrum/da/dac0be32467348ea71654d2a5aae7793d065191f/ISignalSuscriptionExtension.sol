// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;


interface ISignalSuscriptionExtension {
    function getFollowers(address _jasperVault) external view returns(address[] memory);
    function getExectueFollow(address _jasperVault) external view returns(bool);
    function exectueFollowEnd(address _jasperVault) external;
    
    function warningLine() external view returns(uint256);
    function unsubscribeLine() external view returns(uint256);

    function exectueFollowStart(address _jasperVault) external;
    function subscribe(address _jasperVault, address target) external;
    function unsubscribeByExtension(address _jasperVault, address target) external;

}


