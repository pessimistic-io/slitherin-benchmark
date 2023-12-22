// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface ITriggerOrderManager {
    function executeTriggerOrders(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId,
        uint256 _indexPrice
    ) external returns (bool, uint256);

    function validateTPSLTriggers(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId,
        uint256 _indexPrice
    ) external returns (bool);

    function validateTPSLTriggers(
        bytes32 _key,
        uint256 _indexPrice
    ) external view returns (bool);

    function triggerPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external;

    function validateTriggerOrdersData(
        bool _isLong,
        uint256 _indexPrice,
        uint256[] memory _tpPrices,
        uint256[] memory _slPrices,
        uint256[] memory _tpTriggeredAmounts,
        uint256[] memory _slTriggeredAmounts
    ) external pure returns (bool);
}
