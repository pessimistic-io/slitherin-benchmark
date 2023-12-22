// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./AggregatorV3Interface.sol";
import "./SignedSafeMath.sol";
import "./IOracle.sol";

contract ChainlinkFiatOracle is IOracle, AccessControl {
    using SignedSafeMath for int256;

    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Oracle data
    AggregatorV3Interface public ETH_USD;
    // fxAsset address => chainlink ISO_USD oracle address
    mapping(address => address) public assetOracles;

    constructor(address _ETH_USD) {
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        ETH_USD = AggregatorV3Interface(_ETH_USD);
    }

    function getRate(address fxAsset)
        external
        view
        override
        returns (uint256 unitPrice)
    {
        // Get prices
        (, int256 ethPrice, , , ) = ETH_USD.latestRoundData();
        (, int256 ISOPrice, , , ) =
            AggregatorV3Interface(assetOracles[fxAsset]).latestRoundData();

        // Calculate indirect quote
        int256 finalQuote = ISOPrice.mul(1 ether).div(ethPrice);
        unitPrice = uint256(finalQuote >= 0 ? finalQuote : -finalQuote);
    }

    function setOracle(address fxAsset, address oracle)
        external
        override
        onlyOperator
    {
        require(fxAsset != address(0), "Asset cannot be address 0");
        require(oracle != address(0), "Oracle cannot be address 0");
        assetOracles[fxAsset] = oracle;
    }

    modifier onlyOperator() {
        require(
            hasRole(OPERATOR_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Caller is not an operator or admin"
        );
        _;
    }
}

