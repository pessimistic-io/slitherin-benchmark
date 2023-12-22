// SPDX-License-Identifier: UNLINCESED
pragma solidity 0.8.20;

import { LibFeeCollector } from "./LibFeeCollector.sol";
import { LibUtil } from "./LibUtil.sol";

library LibBridge {
    bytes32 internal constant BRIDGE_STORAGE_POSITION =
        keccak256("bridge.storage.position");

    struct BridgeStorage {
        uint256 crosschainFee;
        //chainId -> minFee
        mapping(uint256 => uint256) minFee;
        mapping(address => bool) approvedTokens;
        mapping(uint256 => address) contractTo;
    }

    function _getStorage() internal pure returns (BridgeStorage storage bs) {
        bytes32 position = BRIDGE_STORAGE_POSITION;
        assembly {
            bs.slot := position
        }
    }

    function updateCrosschainFee(uint256 _crosschainFee) internal {
        BridgeStorage storage bs = _getStorage();

        bs.crosschainFee = _crosschainFee;
    }

    function updateMinFee(uint256 _chainId, uint256 _minFee) internal {
        BridgeStorage storage bs = _getStorage();

        bs.minFee[_chainId] = _minFee;
    }

    function addApprovedToken(address _token) internal {
        BridgeStorage storage bs = _getStorage();

        bs.approvedTokens[_token] = true;
    }

    function removeApprovedToken(address _token) internal {
        BridgeStorage storage bs = _getStorage();

        bs.approvedTokens[_token] = false;
    }

    function addContractTo(uint256 _chainId, address _contractTo) internal {
        BridgeStorage storage bs = _getStorage();

        bs.contractTo[_chainId] = _contractTo;
    }

    function removeContractTo(uint256 _chainId) internal {
        BridgeStorage storage bs = _getStorage();

        if (bs.contractTo[_chainId] == address(0)) return;

        bs.contractTo[_chainId] = address(0);
    }

    function getContractTo(uint256 _chainId) internal view returns (address) {
        BridgeStorage storage bs = _getStorage();

        return bs.contractTo[_chainId];
    }

    function getCrosschainFee() internal view returns (uint256) {
        return _getStorage().crosschainFee;
    }

    function getMinFee(uint256 _chainId) internal view returns (uint256) {
        return _getStorage().minFee[_chainId];
    }

    function getApprovedToken(address _token) internal view returns (bool) {
        return _getStorage().approvedTokens[_token];
    }

    function getFeeInfo(uint256 _chainId) internal view returns (uint256, uint256) {
        BridgeStorage storage bs = _getStorage();
        return (bs.crosschainFee, bs.minFee[_chainId]);
    }
}
