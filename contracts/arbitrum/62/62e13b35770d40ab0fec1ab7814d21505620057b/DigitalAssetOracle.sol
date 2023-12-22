// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./AggregatorV3Interface.sol";
import "./SignedSafeMath.sol";
import "./IOracle.sol";

/**
 * @notice The oracle to be used for assets that can be directly quoted in ETH. Eg: BTC/ETH
 * @dev The oracles need to quote in ASSET/ETH
 */
contract DigitalAssetOracle is IOracle, AccessControl {
    using SignedSafeMath for int256;

    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // fxAsset address => chainlink ISO_USD oracle address
    mapping(address => address) public assetOracles;

    constructor() {
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
    }

    /**
     * @notice Returns the indirect quote ETH/ASSET from an external oracle quoting in ASSET/ETH
     * @param fxAsset the asset to quote for
     * @return unitPrice the price of a single unit of the asset in ETH
     */
    function getRate(address fxAsset)
        external
        view
        override
        returns (uint256 unitPrice)
    {
        // Get price
        (, int256 asset_eth, , , ) =
            AggregatorV3Interface(assetOracles[fxAsset]).latestRoundData();
        unitPrice = uint256(asset_eth >= 0 ? asset_eth : -asset_eth);
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

