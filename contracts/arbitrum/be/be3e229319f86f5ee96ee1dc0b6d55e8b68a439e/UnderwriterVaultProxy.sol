// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {Proxy} from "./Proxy.sol";
import {ERC20MetadataStorage} from "./ERC20MetadataStorage.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {ERC4626BaseStorage} from "./ERC4626BaseStorage.sol";

import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";
import {IVaultRegistry} from "./IVaultRegistry.sol";

contract UnderwriterVaultProxy is Proxy {
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;

    // Constants
    bytes32 public constant VAULT_TYPE = keccak256("UnderwriterVault");
    address internal immutable VAULT_REGISTRY;

    constructor(
        address vaultRegistry,
        address base,
        address quote,
        address oracleAdapter,
        string memory name,
        string memory symbol,
        bool isCall
    ) {
        VAULT_REGISTRY = vaultRegistry;

        ERC20MetadataStorage.Layout storage metadata = ERC20MetadataStorage.layout();
        metadata.name = name;
        metadata.symbol = symbol;
        metadata.decimals = 18;

        ERC4626BaseStorage.layout().asset = isCall ? base : quote;

        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();

        bytes memory settings = IVaultRegistry(VAULT_REGISTRY).getSettings(VAULT_TYPE);
        l.updateSettings(settings);

        l.isCall = isCall;
        l.base = base;
        l.quote = quote;

        uint8 baseDecimals = IERC20Metadata(base).decimals();
        uint8 quoteDecimals = IERC20Metadata(quote).decimals();
        l.baseDecimals = baseDecimals;
        l.quoteDecimals = quoteDecimals;

        l.lastTradeTimestamp = block.timestamp;
        l.oracleAdapter = oracleAdapter;
    }

    receive() external payable {}

    /// @inheritdoc Proxy
    function _getImplementation() internal view override returns (address) {
        return IVaultRegistry(VAULT_REGISTRY).getImplementation(VAULT_TYPE);
    }

    /// @notice get address of implementation contract
    /// @return implementation address
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }
}

