// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2022 Dai Foundation
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

import "./ISmartWallet.sol";
import "./ISmartWalletFactory.sol";
import "./ISmartWalletRegistry.sol";
import "./Clones.sol";
import "./Ownable.sol";

contract SmartWalletRegistry is Ownable, ISmartWalletRegistry {
	ISmartWalletFactory public smartWalletFactory;

  struct UserProfile {
    address smartWallet;
    uint96 seed;
  }

  mapping( /* user */ address => UserProfile) public userProfiles;
  // linked list of historical smart wallet implementations. Last element refers to itself.
  mapping( /* implementation */ address => /* prevImplementation */ address) public prevImplementations; 

	function setSmartWalletFactory(ISmartWalletFactory newFactory) public onlyOwner {
		require(address(newFactory) != address(0), "SWR: implementation required");
    address newImplementation = newFactory.smartWalletImplementation();
    
    ISmartWalletFactory oldFactory = smartWalletFactory;
    address oldImplementation;

    if (address(oldFactory) != address(0)) {
      oldImplementation = oldFactory.smartWalletImplementation();
      if (newImplementation != oldImplementation) {
        prevImplementations[newImplementation] = oldImplementation;
      }
    } else {
      prevImplementations[newImplementation] = newImplementation;
    }

    smartWalletFactory = newFactory;
    emit SetSmartWalletFactory(oldFactory, newFactory);
	}

  function getUserWallet(address user) public view returns (address, uint96) {
    UserProfile memory profile = userProfiles[user];

		if (profile.smartWallet != address(0)) {
      try ISmartWallet(profile.smartWallet).owner() returns (address owner) {
        if (owner == user) {
          return (profile.smartWallet, 0);
        }
      } catch {
        // the wallet was selfdestructed
      }
    }

    return smartWalletFactory.findNewSmartWalletAddress(user, profile.seed);
  }

	function build(address user) external returns (address) {
		(address smartWallet, uint96 seed) = getUserWallet(user);
    require(seed != 0, "SWR: already registered to user"); 
    userProfiles[user] = UserProfile(smartWallet, seed);
    return ISmartWalletFactory(smartWalletFactory).build(user, seed);
	}

	function buildAndExec(bytes20 target, bytes calldata data) external payable returns (bytes memory response) {
    // Prevent pre-creating non-empty wallets for other users for security reasons
		address user = msg.sender;
		// We want to avoid creating a wallet for a contract address that might not be able to handle wallets, then losing the funds
		require(tx.origin == msg.sender, "SWR: usr is a contract"); // solhint-disable-line avoid-tx-origin

    (address smartWallet, uint96 seed) = getUserWallet(user);
    require(seed != 0, "SWR: already registered to user"); 
    userProfiles[user] = UserProfile(smartWallet, seed);
    response = smartWalletFactory.buildAndExec{ value: msg.value }(user, seed, target, data);
	}

  function getWalletImplementation(address smartWallet) external view returns (address) {
		return smartWalletFactory.getWalletImplementation(smartWallet);
	}

	// This function needs to be used carefully, you should only claim a smart wallet you trust on.
	// A smart wallet might be set up with a dispatcher or just simple allowances that might make an
	// attacker to take funds that are sitting in the smart wallet.
	function claim(address smartWallet, bool allowReplacing) external returns (address) {
    require(smartWallet != address(0), "SWR: smartWallet required");
    address walletImplementation = smartWalletFactory.getWalletImplementation(smartWallet);
		require(prevImplementations[walletImplementation] != address(0), "SWR: not acc from this registry");
		address walletOwner = ISmartWallet(payable(smartWallet)).owner();
		require(msg.sender == smartWallet || msg.sender == walletOwner, "SWR: unauthorized claim");

    (address oldWallet, uint seed) = getUserWallet(walletOwner);
    userProfiles[walletOwner].smartWallet = smartWallet;
    
    if (seed == 0) {
      require(allowReplacing, "SWR: already registered to user");
    } else {
      oldWallet = address(0);
    }

    emit SmartWalletClaimed(smartWallet, walletOwner, oldWallet);
    return oldWallet;
  }

  function dispatcher() external view returns (address) {
    return smartWalletFactory.dispatcher();
  }

  function smartWalletImplementation() external view returns (address) {
    return smartWalletFactory.smartWalletImplementation();
  }
}

