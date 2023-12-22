// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import "./BaseToken.sol";
import { IBaseMintableToken } from "./Interfaces.sol";

contract BaseMintableToken is IBaseMintableToken, BaseToken {
  mapping(address => bool) public isMinter;
  mapping(address => bool) public isBurner;

  constructor(
    string memory _name,
    string memory _symbol,
    bool _isTransferPermissioned
  ) BaseToken(_name, _symbol, _isTransferPermissioned) {}

  function mint(address _account, uint _amount) external {
    if (!isMinter[msg.sender]) revert UNAUTHORIZED(string.concat(symbol(), ': ', '!minter'));
    _mint(_account, _amount);
  }

  function burn(address _account, uint _amount) external {
    if (!isBurner[msg.sender]) revert UNAUTHORIZED(string.concat(symbol(), ': ', '!burner'));
    _burn(_account, _amount);
  }

  function setMinter(address _minter, bool _isActive) external onlyOwner {
    isMinter[_minter] = _isActive;
  }

  function setBurner(address _burner, bool _isActive) external onlyOwner {
    isBurner[_burner] = _isActive;
  }
}

