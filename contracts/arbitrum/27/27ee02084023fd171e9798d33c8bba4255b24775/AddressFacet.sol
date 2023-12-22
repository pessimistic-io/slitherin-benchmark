// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {BFacetOwner} from "./BFacetOwner.sol";
import {LibAddress} from "./LibAddress.sol";

contract AddressFacet is BFacetOwner {
    using LibAddress for address;

    event LogSetGasPriceOracle(address indexed gasPriceOracle);

    function setGasPriceOracle(address _gasPriceOracle) external onlyOwner {
        _gasPriceOracle.setGasPriceOracle();
        emit LogSetGasPriceOracle(_gasPriceOracle);
    }

    function getGasPriceOracle()
        external
        view
        returns (address gasPriceOracle)
    {
        gasPriceOracle = LibAddress.getGasPriceOracle();
    }
}

