// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract SlugArbitrum is ERC20, ERC20Burnable, Ownable {
  // sandwicher variables
  address public sandwicherMasterAddress;
  mapping(address => bool) public sandwicherWhitelist;
  bool public antiSandwichEnabled;
  mapping(uint256 => mapping(address => bool)) public transactedCurrentBlock; // keeps track of the transactions of current block

  constructor() ERC20("UNLUCKY SLUG", "SLUG") {
    sandwicherMasterAddress = msg.sender;
    _mint(msg.sender, 1301301301301 * 10 ** decimals());
  }

  /////////////////////////
  // sandwicher functions
  ////////////////////////

  // only deployer can whitelist allowed addresses than can do multiple tx per block
  modifier onlySandwicherMaster() {
    require(
      msg.sender == sandwicherMasterAddress,
      "SLUG: not the sandwicher master, scammer motherfucker"
    );
    _;
  }

  function changeSandwicherMasterAddress(
    address _sandwicherMasterAddress
  ) external onlySandwicherMaster {
    sandwicherMasterAddress = _sandwicherMasterAddress;
  }

  // only for CEX hot wallets and DEX pools
  function isSandwicherAllowed(address account) public view returns (bool) {
    return sandwicherWhitelist[account];
  }

  function setSandwicherStatus(
    address account,
    bool status
  ) external onlySandwicherMaster {
    sandwicherWhitelist[account] = status;
  }

  function setAntiSandwichEnabled(bool status) external onlySandwicherMaster {
    antiSandwichEnabled = status;
  }

  /////////////////////////
  // before token transfer logic
  /////////////////////////
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual override {
    // check if anti sandwich is enabled
    if (antiSandwichEnabled) {
      if (!isSandwicherAllowed(to)) {
        require(
          !transactedCurrentBlock[block.number][from],
          "SLUG: sandwich protection, wait 1 block to transact again, or surrounder to @_slugfather_"
        );
        transactedCurrentBlock[block.number][to] = true;
      }
    }

    super._beforeTokenTransfer(from, to, amount);
  }
}

