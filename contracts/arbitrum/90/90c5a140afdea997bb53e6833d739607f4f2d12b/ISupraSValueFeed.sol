// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ISupraSValueFeed {
    struct dataWithoutHcc {
        uint256 round;
        uint256 decimals;
        uint256 time;
        uint256 price;
    }

    struct dataWithHcc {
        uint256 round;
        uint256 decimals;
        uint256 time;
        uint256 price;
        uint256 historyConsistent;
    }

    function getTimestamp(uint256 _tradingPair) external view returns (uint256);

    function getSvalueWithHCC(uint256 _pairIndex)
        external
        view
        returns (dataWithHcc memory);

    function getSvaluesWithHCC(uint256[] memory _pairIndexes)
        external
        view
        returns (dataWithHcc[] memory);

    function getSvalue(uint256 _pairIndex)
        external
        view
        returns (dataWithoutHcc memory);

    function getSvalues(uint256[] memory _pairIndexes)
        external
        view
        returns (dataWithoutHcc[] memory);
}

