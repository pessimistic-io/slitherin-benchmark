// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TransparentUpgradeableProxy.sol";

/**
 * @title LayerConnectorsProxy
 * @dev This contract is a transparent upgradeable proxy for the LayerConnectorsV2 contract.
 * It allows for the logic contract (LayerConnectorsV2) to be upgraded while maintaining the same storage and address.
 */
contract LayerConnectorsProxy is TransparentUpgradeableProxy {

    /**
     * @dev Initializes the proxy with the initial logic contract, admin address, and any initial data.
     * @param _logic Address of the initial logic contract.
     * @param admin_ Address of the admin who can upgrade the proxy.
     * @param _data Data to be passed as msg.data to the logic contract for any initialization.
     */
    constructor(address _logic, address admin_, bytes memory _data) 
        public 
        TransparentUpgradeableProxy(_logic, admin_, _data) 
    {}
}

