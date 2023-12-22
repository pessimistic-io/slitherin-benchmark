// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./IAggregatorV3Interface.sol";

// Mock aggregator interface contract that allows having an aggregator to update the price.
contract MockAggregatorV3Interface is IAggregatorV3Interface, AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    int256 private price;

    constructor(int256 _price) {
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        price = _price;
    }

    modifier onlyOperator() {
        require(
            hasRole(OPERATOR_ROLE, msg.sender),
            "Caller is not an operator"
        );
        _;
    }

    function setPrice(int256 _price) external onlyOperator {
        price = _price;
    }

    function latestRoundData()
        public
        view
        override
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        return (
            55340232221128675885,
            price,
            1614139932,
            1614139990,
            55340232221128675885
        );
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return latestRoundData();
    }

    function decimals() external view override returns (uint8) {
        return 18;
    }

    function description() external view override returns (string memory) {
        return "mock";
    }

    function version() external view override returns (uint256) {
        return 1;
    }
}

