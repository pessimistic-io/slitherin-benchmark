// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import { ICegaEntry } from "./ICegaEntry.sol";
import { CegaEntry } from "./CegaEntry.sol";
import { IAddressManager } from "./IAddressManager.sol";
import { IACLManager } from "./IACLManager.sol";

contract AddressManager is IAddressManager {
    bytes32 private constant CEGA_ENTRY = "CEGA_ENTRY";
    bytes32 private constant CEGA_ORACLE = "CEGA_ORACLE";
    bytes32 private constant ACL_MANAGER = "ACL_MANAGER";
    bytes32 private constant REDEPOSIT_MANAGER = "REDEPOSIT_MANAGER";
    bytes32 private constant TRADE_WINNER_NFT = "TRADE_WINNER_NFT";
    bytes32 private constant CEGA_FEE_RECEIVER = "CEGA_FEE_RECEIVER";

    // Map of registered addresses (identifier => registeredAddress)
    mapping(bytes32 => address) private _addresses;

    modifier onlyCegaAdmin() {
        require(
            IACLManager(_addresses[ACL_MANAGER]).isCegaAdmin(msg.sender),
            "AddressManager: not cega admin"
        );
        _;
    }

    constructor(address aclManager) {
        _setAddress(ACL_MANAGER, aclManager);
    }

    function getCegaOracle() external view returns (address) {
        return _addresses[CEGA_ORACLE];
    }

    function getCegaEntry() external view returns (address) {
        return _addresses[CEGA_ENTRY];
    }

    function getCegaFeeReceiver() external view returns (address) {
        return _addresses[CEGA_FEE_RECEIVER];
    }

    function getACLManager() external view returns (address) {
        return _addresses[ACL_MANAGER];
    }

    function getRedepositManager() external view returns (address) {
        return _addresses[REDEPOSIT_MANAGER];
    }

    function getTradeWinnerNFT() external view returns (address) {
        return _addresses[TRADE_WINNER_NFT];
    }

    function getAddress(bytes32 id) external view returns (address) {
        return _addresses[id];
    }

    function setCegaEntry(address newAddress) external onlyCegaAdmin {
        _setAddress(CEGA_ENTRY, newAddress);
    }

    function setTradeWinnerNFT(address newAddress) external onlyCegaAdmin {
        _setAddress(TRADE_WINNER_NFT, newAddress);
    }

    function setCegaOracle(address newAddress) external onlyCegaAdmin {
        _setAddress(CEGA_ORACLE, newAddress);
    }

    function setRedepositManager(address newAddress) external onlyCegaAdmin {
        _setAddress(REDEPOSIT_MANAGER, newAddress);
    }

    function setCegaFeeReceiver(address newAddress) external onlyCegaAdmin {
        _setAddress(CEGA_FEE_RECEIVER, newAddress);
    }

    function setAddress(bytes32 id, address newAddress) external onlyCegaAdmin {
        _setAddress(id, newAddress);
    }

    function updateCegaEntryImpl(
        ICegaEntry.ProxyImplementation[] calldata implementationParams,
        address _init,
        bytes calldata _calldata
    ) external onlyCegaAdmin {
        _updateCegaEntryImpl(
            CEGA_ENTRY,
            implementationParams,
            _init,
            _calldata
        );

        emit CegaEntryUpdated(implementationParams, _init, _calldata);
    }

    function _updateCegaEntryImpl(
        bytes32 id,
        ICegaEntry.ProxyImplementation[] calldata implementationParams,
        address _init,
        bytes calldata _calldata
    ) private {
        address proxyAddress = _addresses[id];

        ICegaEntry proxy;

        if (proxyAddress == address(0)) {
            proxy = ICegaEntry(address(new CegaEntry(address(this))));
            proxy.updateImplementation(implementationParams, _init, _calldata);
            _addresses[id] = proxyAddress = address(proxy);
            emit CegaEntryCreated(id, proxyAddress, implementationParams);
        } else {
            proxy = ICegaEntry(payable(proxyAddress));

            proxy.updateImplementation(implementationParams, _init, _calldata);
            emit CegaEntryUpdated(implementationParams, _init, _calldata);
        }
    }

    function _setAddress(bytes32 id, address newAddress) private {
        address oldAddress = _addresses[id];
        _addresses[id] = newAddress;
        emit AddressSet(id, oldAddress, newAddress);
    }
}

