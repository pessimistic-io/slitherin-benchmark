// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {LibTermStorage} from "./LibTermStorage.sol";
import {LibYieldGenerationStorage} from "./LibYieldGenerationStorage.sol";
import {LibDiamond} from "./LibDiamond.sol";

contract DiamondInit {
    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    function init(
        address _aggregatorAddressEthUsd,
        address _aggregatorAddressUsdUsdc,
        address _zapAddress, // Zaynfi Zap address
        address _vaultAddress, // Zaynfi Vault address
        bool _yieldLock
    ) external onlyOwner {
        LibTermStorage.TermConsts storage termConsts = LibTermStorage._termConsts();
        LibYieldGenerationStorage.YieldProviders storage yieldProvider = LibYieldGenerationStorage
            ._yieldProviders();

        termConsts.aggregatorsAddresses["ETH/USD"] = _aggregatorAddressEthUsd;
        termConsts.aggregatorsAddresses["USDC/USD"] = _aggregatorAddressUsdUsdc;

        yieldProvider.providerAddresses["ZaynZap"] = _zapAddress;
        yieldProvider.providerAddresses["ZaynVault"] = _vaultAddress;

        LibYieldGenerationStorage._yieldLock().yieldLock = _yieldLock;
    }
}

