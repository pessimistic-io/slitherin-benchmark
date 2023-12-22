// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.
//   _   _ __  ____  __
//  | | | |  \/  \ \/ /
//  | |_| | |\/| |\  /
//  |  _  | |  | |/  \
//  |_| |_|_|  |_/_/\_\
//

pragma solidity 0.8.18;

import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

contract EsHMX is ERC20Upgradeable, OwnableUpgradeable {
  mapping(address => bool) public isTransferrer;
  mapping(address => bool) public isMinter;
  uint256 public maxTotalSupply;

  event EsHMX_SetMinter(address minter, bool prevAllow, bool newAllow);

  error EsHMX_isNotTransferrer();
  error EsHMX_NotMinter();
  error EsHMX_ExceedTotalSupply();

  modifier onlyMinter() {
    if (!isMinter[msg.sender]) revert EsHMX_NotMinter();
    _;
  }

  function initialize() external initializer {
    OwnableUpgradeable.__Ownable_init();
    ERC20Upgradeable.__ERC20_init("Escrowed HMX", "EsHMX");

    maxTotalSupply = 10_000_000 ether;
  }

  function setMinter(address minter, bool allow) external onlyOwner {
    emit EsHMX_SetMinter(minter, isMinter[minter], allow);
    isMinter[minter] = allow;
  }

  function mint(address to, uint256 amount) public onlyMinter {
    if (totalSupply() + amount > maxTotalSupply) revert EsHMX_ExceedTotalSupply();
    _mint(to, amount);
  }

  function setTransferrer(address transferrer, bool isActive) external onlyOwner {
    isTransferrer[transferrer] = isActive;
  }

  function _transfer(address from, address to, uint256 amount) internal virtual override {
    if (!isTransferrer[msg.sender]) revert EsHMX_isNotTransferrer();

    super._transfer(from, to, amount);
  }

  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public virtual override returns (bool) {
    _transfer(from, to, amount);
    return true;
  }
}

