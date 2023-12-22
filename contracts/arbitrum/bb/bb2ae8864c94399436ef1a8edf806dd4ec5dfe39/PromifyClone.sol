// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./PromifyArbitrum.sol";
import "./CloneFactory.sol";
import "./Ownable.sol";


contract PromifyClone is Ownable, CloneFactory {

  address public libraryAddress;

  event PromifyCreated(address newThingAddress);

  function setLibraryAddress(address _libraryAddress) public onlyOwner {
    libraryAddress = _libraryAddress;
  }

  function createThing(string memory name, string memory symbol, address addressPROM, uint256 starAllo, address celebrityAddress, address _DAO) public onlyOwner {
    address clone = createClone(libraryAddress);
    PromifyArbitrum(clone).initialize(name, symbol, addressPROM, starAllo, celebrityAddress, _DAO);
    emit PromifyCreated(clone);
  }
}
