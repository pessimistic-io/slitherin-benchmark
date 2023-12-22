// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Address } from "./Address.sol";
import { Ownable } from "./Ownable.sol";

import { IPriceOracleManager } from "./IPriceOracleManager.sol";
import { IOracleWrapper } from "./IOracleWrapper.sol";

error notContract();
error duplicateWrapper(address);
error wrapperNotRegistered(address);
error priceNotUpdated(address);
error oracleCorrupted(address);

contract PriceOracleManager is IPriceOracleManager, Ownable {
    using Address for address;

    // This is a mapping of wrapper addresses for a particular target asset and all the assets are measured in USD by default
    // maps address(underlying)  => address(wrapper)
    // Wherein, the underlying is the target asset
    // Eg: If we consider ETH/USD pair, ETH will be quoted in terms of USD by default
    mapping(address => address) public wrapperAddressMap;

    uint256 public constant TIME_OFFSET = 4 hours;

    function setWrapper(address _underlying, address _wrapperAddress) external override onlyOwner {
        if (!_wrapperAddress.isContract()) revert notContract();
        if (wrapperAddressMap[_underlying] != address(0)) revert duplicateWrapper(_wrapperAddress);

        wrapperAddressMap[_underlying] = _wrapperAddress;

        emit NewWrapperRegistered(_underlying, _wrapperAddress);
    }

    function updateWrapper(address _underlying, address _wrapperAddress) external override onlyOwner {
        if (!_wrapperAddress.isContract()) revert notContract();
        if (wrapperAddressMap[_underlying] == address(0)) revert wrapperNotRegistered(_wrapperAddress);

        wrapperAddressMap[_underlying] = _wrapperAddress;

        emit WrapperUpdated(_underlying, _wrapperAddress);
    }

    /**
     * @dev This function is used to get the external price of the underlying asset
     * @param _underlying is the asset whose price is desired
     * e.g. if the underlying is ETH and the strike is USDC, then the returned price will represent USDC per ETH.
     * @param _data contains any flags which the active oracle may use.
     */
    function getExternalPrice(
        address _underlying,
        bytes calldata _data
    ) external view override returns (uint256 price, uint8 decimals, bool success) {
        IOracleWrapper wrapper = IOracleWrapper(wrapperAddressMap[_underlying]);

        if (address(wrapper) == address(0)) revert wrapperNotRegistered(address(wrapper));

        return wrapper.getExternalPrice(_underlying, _data);
    }
}

