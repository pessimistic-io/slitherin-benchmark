// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.15;

/**
 * @title Interface of Strateg Asset Buffer
 * @author Bliiitz
 * @notice Minimalistic mutualized buffer for vault. It is used to put buffered assets outside the vault strategies accounting
 */
interface IStrategAssetBuffer {
    function putInBuffer(address _asset, uint256 _amount) external;
}

