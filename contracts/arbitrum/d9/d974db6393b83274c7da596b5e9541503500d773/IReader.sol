//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IReaderStorage} from "./IReaderStorage.sol";

interface IReader is IReaderStorage {
    function getDex() external view returns (address[] memory);
    function getBaseTokenEligible(address _baseToken) external view returns (bool);
    function getPrice(address _baseToken) external view returns (uint256, uint256);
    function checkPrices(uint256 _entry, uint256 _target, address _baseToken, bool _tradeDirection)
        external
        view
        returns (bool);
}

