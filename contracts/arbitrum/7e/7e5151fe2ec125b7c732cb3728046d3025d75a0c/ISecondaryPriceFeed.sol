// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0 <0.8.0;

interface ISecondaryPriceFeed {
    function getPrice(string memory _token, uint256 _referencePrice, bool _maximise) external view returns (uint256);

    function getIndexPrice(string memory _token, uint256 _refPrice, bool _maximise) external view returns (uint256);
}

