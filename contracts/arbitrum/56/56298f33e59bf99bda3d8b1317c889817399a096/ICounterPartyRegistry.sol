// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

interface ICounterPartyRegistry {
    function getCounterParty(address) external view returns (bool);
    function getSwapContract(address) external view returns (bool);
    function getSwapContractManager(address) external view returns (bool);
    function getMaxMarginTransferAmount(address) external view returns (uint256);
    function setMaxMarginTransferAmount(address, uint256) external;
    function addSwapContract(address) external;
    function addCounterParty(address) external;
}
