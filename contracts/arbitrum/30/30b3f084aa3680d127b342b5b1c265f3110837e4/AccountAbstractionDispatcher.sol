// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Copyright (C) 2023 VALK
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.18;
import "./ManagedDispatcher.sol";
import "./IAccount.sol";
import "./EIP4337Scripts.sol";
import "./Ownable.sol";
import "./IDispatcher.sol";

interface IAccountAbstractionDispatcher is IDispatcher {
  function accountAbstractionScripts() external view returns (address);
  function fallbackDispatcher() external view returns (address);
  function entryPoint() external view returns (address);
}

/**
 * @title Dispatcher supporting EIP-4337
 */
contract AccountAbstractionDispatcher is ManagedDispatcher, IAccountAbstractionDispatcher {

  address immutable public accountAbstractionScripts;
  address immutable public fallbackDispatcher;
  address immutable public entryPoint; 
  
  constructor (address _accountAbstractionScripts, address _fallbackDispatcher) {
    accountAbstractionScripts = _accountAbstractionScripts;
    fallbackDispatcher = _fallbackDispatcher;
    entryPoint = EIP4337Scripts(_accountAbstractionScripts).entryPoint();
  }

  function dispatch(
		address source,
    address wallet,
    Account calldata executor,
		bytes20 target,
		bytes4 selector
	) external override returns (address dispatchedTarget) {

    if (source == entryPoint) {
      // hardcoded dispatching because it is not allowed to use shared storage inside of validateUserOp 
      if (
        executor.accountType == OWNED_SMART_WALLET_ACCOUNT &&
        target == bytes20(0) && 
        selector == IAccount.validateUserOp.selector
      ) {
        return accountAbstractionScripts;
      }
  
      if (target == bytes20(0) && executor.accountType != OWNED_SMART_WALLET_ACCOUNT) {
        // no calls from third-party executors to wallet
        return address(0);
      }

      // calls from entryPoint are already authorized with validateUserOp 
      return getTargeOrDefault(executor.accountType, target, selector);
    } 

    return IDispatcher(fallbackDispatcher).dispatch(source, wallet, executor, target, selector);
	}
}
