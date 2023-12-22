// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { Ownable } from "./Ownable.sol";
import { AppStorage } from "./LibAppStorage.sol";
import { PublicKey } from "./LibOracle.sol";
import { C } from "./C.sol";

contract ConstantsFacet is Ownable {
    AppStorage internal s;

    /*------------------------*
     * PUBLIC WRITE FUNCTIONS *
     *------------------------*/

    function setCollateral(address _collateral) external onlyOwner {
        s.constants.collateral = _collateral;
    }

    function setMuonAppId(uint256 _muonAppId) external onlyOwner {
        s.constants.muonAppIdV2 = _muonAppId;
    }

    function setMuonPublicKey(uint256 x, uint8 parity) external onlyOwner {
        s.constants.muonPublicKey = PublicKey(x, parity);
    }

    function setMuonGatewaySigner(address _muonGatewaySigner) external onlyOwner {
        s.constants.muonGatewaySigner = _muonGatewaySigner;
    }

    function setProtocolFee(uint256 _protocolFee) external onlyOwner {
        s.constants.protocolFee = _protocolFee;
    }

    function setLiquidationFee(uint256 _liquidationFee) external onlyOwner {
        s.constants.liquidationFee = _liquidationFee;
    }

    function setProtocolLiquidationShare(uint256 _protocolLiquidationShare) external onlyOwner {}

    function setCVA(uint256 _cva) external onlyOwner {
        s.constants.cva = _cva;
    }

    function setRequestTimeout(uint256 _requestTimeout) external onlyOwner {
        s.constants.requestTimeout = _requestTimeout;
    }

    function setMaxOpenPositionsCross(uint256 _maxOpenPositionsCross) external onlyOwner {
        s.constants.maxOpenPositionsCross = _maxOpenPositionsCross;
    }

    /*-----------------------*
     * PUBLIC VIEW FUNCTIONS *
     *-----------------------*/

    function getPrecision() external pure returns (uint256) {
        return C.getPrecision();
    }

    function getPercentBase() external pure returns (uint256) {
        return C.getPercentBase();
    }

    function getCollateral() external view returns (address) {
        return C.getCollateral();
    }

    function getMuonAppId() external view returns (uint256) {
        return C.getMuonAppId();
    }

    function getMuonPublicKey() external view returns (PublicKey memory) {
        return C.getMuonPublicKey();
    }

    function getMuonGatewaySigner() external view returns (address) {
        return C.getMuonGatewaySigner();
    }

    function getProtocolFee() external view returns (uint256) {
        return C.getProtocolFee().value;
    }

    function getLiquidationFee() external view returns (uint256) {
        return C.getLiquidationFee().value;
    }

    function getProtocolLiquidationShare() external view returns (uint256) {
        return C.getProtocolLiquidationShare().value;
    }

    function getCVA() external view returns (uint256) {
        return C.getCVA().value;
    }

    function getRequestTimeout() external view returns (uint256) {
        return C.getRequestTimeout();
    }

    function getMaxOpenPositionsCross() external view returns (uint256) {
        return C.getMaxOpenPositionsCross();
    }
}

