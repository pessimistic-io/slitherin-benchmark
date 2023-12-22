// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ITicketCollectionFactory {
    function createTicketCollection(
        string memory _name,
        string memory _symbol,
        string memory _baseURI
    ) external returns (address);
}
