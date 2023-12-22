// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Ownable } from "./Ownable.sol";
import { Address } from "./Address.sol";

import { IAddressProvider } from "./IAddressProvider.sol";

bytes32 constant CREDIT_AGGREGATOR = "CREDIT_AGGREGATOR";
bytes32 constant GMX_REWARD_ROUTER = "GMX_REWARD_ROUTER";
bytes32 constant GMX_REWARD_ROUTER_V1 = "GMX_REWARD_ROUTER_V1";

contract AddressProvider is Ownable, IAddressProvider {
    using Address for address;

    mapping(bytes32 => address) public addresses;

    constructor() {
        emit AddressSet("ADDRESS_PROVIDER", address(this));
    }

    function getGmxRewardRouter() external view override returns (address) {
        return _getAddress(GMX_REWARD_ROUTER);
    }

    function setGmxRewardRouter(address _v) external onlyOwner {
        require(_v != address(0), "AddressProvider: _v cannot be 0x0");

        _setAddress(GMX_REWARD_ROUTER, _v);
    }

    function getGmxRewardRouterV1() external view override returns (address) {
        return _getAddress(GMX_REWARD_ROUTER_V1);
    }

    function setGmxRewardRouterV1(address _v) external onlyOwner {
        require(_v != address(0), "AddressProvider: _v cannot be 0x0");

        _setAddress(GMX_REWARD_ROUTER_V1, _v);
    }

    function getCreditAggregator() external view override returns (address) {
        return _getAddress(CREDIT_AGGREGATOR);
    }

    function setCreditAggregator(address _v) external onlyOwner {
        require(_v != address(0), "AddressProvider: _v cannot be 0x0");

        _setAddress(CREDIT_AGGREGATOR, _v);
    }

    /// @return Address of key, reverts if the key doesn't exist
    function _getAddress(bytes32 _key) internal view returns (address) {
        address result = addresses[_key];
        require(result != address(0), "AddressProvider: Address not found");
        return result;
    }

    /// @dev Sets address to map by its key
    /// @param _key Key in string format
    /// @param _value Address
    function _setAddress(bytes32 _key, address _value) internal {
        addresses[_key] = _value;
        emit AddressSet(_key, _value);
    }
}

