// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import "./IComposable.sol";

import "./Initializable.sol";

abstract contract Composable is Initializable, IComposable {
  // Doesn't use "name" due to IERC20 using "name"
  bytes32 public override contractName;
  // Version is global, and not per-interface, as interfaces aren't "DAO" and "FrabricDAO"
  // Any version which changes the API would change the interface ID, so checking
  // for supported functionality should be via supportsInterface, not version
  uint256 public override version;
  mapping(bytes4 => bool) public override supportsInterface;

  // While this could probably get away with 5 variables, and other contracts
  // with 20, the fact this is free (and a permanent decision) leads to using
  // these large gaps
  uint256[100] private __gap;

  // Code should set its name so Beacons can identify code
  // That said, code shouldn't declare support for interfaces or have any version
  // Hence this
  // Due to solidity requirements, final constracts (non-proxied) which call init
  // yet still use constructors will have to call this AND init. It's a minor
  // gas inefficiency not worth optimizing around
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(string memory name) {
    contractName = keccak256(bytes(name));

    supportsInterface[type(IERC165Upgradeable).interfaceId] = true;
    supportsInterface[type(IComposable).interfaceId] = true;
  }

  function __Composable_init(string memory name, bool finalized) internal onlyInitializing {
    contractName = keccak256(bytes(name));
    if (!finalized) {
      version = 1;
    } else {
      version = type(uint256).max;
    }

    supportsInterface[type(IERC165Upgradeable).interfaceId] = true;
    supportsInterface[type(IComposable).interfaceId] = true;
  }
}

