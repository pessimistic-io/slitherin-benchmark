// SPDX-License-Identifier: ISC
/**
* By using this software, you understand, acknowledge and accept that Tetu
* and/or the underlying software are provided “as is” and “as available”
* basis and without warranties or representations of any kind either expressed
* or implied. Any use of this open source software released under the ISC
* Internet Systems Consortium license is done at your own risk to the fullest
* extent permissible pursuant to applicable law any and all liability as well
* as all warranties, including any fitness for a particular purpose with respect
* to Tetu and/or the underlying software and the use thereof are disclaimed.
*/

pragma solidity ^0.8.9;

import "./Controller.sol";

/// @title A central contract for control everything.
///        Governance is a Multi-Sig Wallet
/// @dev Use with TetuProxy
/// @author belbix
contract PreonController is Controller {

  /// @notice Return true if the given address:
  ///         - is not smart contract
  ///         - added to whitelist
  ///         - governance address
  ///         - hardworker
  ///         - reward distributor
  ///         - registered vault
  ///         - registered strategy
  /// @param _adr Address for check
  /// @return true if the address allowed
  function isAllowedUser(address _adr) external view override returns (bool) {
    return whiteList[_adr];
  }

}

