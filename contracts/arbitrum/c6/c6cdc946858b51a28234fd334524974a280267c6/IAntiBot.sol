// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IAntiBot {
    function setOperator(address _user) external;

    function removeOperator(address _operator) external;

    function enabledWhiteList(bool _enabled) external;

    function setIpPairAddress(address _ipPairAddress) external;

    function setSellCoolDown(uint256 _sellCoolDown) external;

    function setMaxSellAmount(uint256 _maxSellAmount) external;

    function setBuyCoolDown(uint256 _buyCoolDown) external;

    function setMaxBuyAmount(uint256 _maxBuyAmount) external;

    function addUsersToBlackList(address[] memory _users) external;

    function removeUsersFromBlackList(address[] memory _users) external;

    function addUsersToWhiteList(address[] memory _users) external;

    function removeUsersFromWhiteList(address[] memory _users) external;

    function protect(address _sender, address _receiver, uint256 _amount) external;
}
