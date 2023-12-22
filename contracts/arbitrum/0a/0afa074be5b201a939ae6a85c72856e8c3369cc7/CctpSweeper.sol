// SPDX-License-Identifier: MIT

pragma solidity >=0.8.21;

import {Initializable} from "./Initializable.sol";

import {ICctpSweeper} from "./ICctpSweeper.sol";
import {ITokenMessenger} from "./ITokenMessenger.sol";
import {IERC20} from "./IERC20.sol";

import {HasAdmin} from "./HasAdmin.sol";

import {CctpTransfers} from "./CctpTransfers.sol";

contract CctpSweeper is HasAdmin, ICctpSweeper {
  IERC20 public override usdc;
  ITokenMessenger public override tokenMessenger;
  uint32 public override destinationDomain;

  /**
   * @notice Initialize the sweeper
   * @param _owner the address that can upgrade the contract and call `sweepToCctp`
   * @param _usdc USDC address
   * @param _tokenMessenger TokenMessenger
   * @param _destinationDomain domain to send USDC to
   */
  function initialize(
    address _owner,
    IERC20 _usdc,
    ITokenMessenger _tokenMessenger,
    uint32 _destinationDomain
  ) external initializer {
    __AccessControl_init();
    _setupRole(OWNER_ROLE, _owner);
    _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
    usdc = _usdc;
    tokenMessenger = _tokenMessenger;
    destinationDomain = _destinationDomain;
  }

  /// @inheritdoc ICctpSweeper
  function sweep(address addr) external override onlyAdmin {
    uint256 amountToSweep = usdc.balanceOf(addr);

    if (usdc.allowance(addr, address(this)) < amountToSweep) {
      revert InsufficientAllowance(addr);
    }

    usdc.transferFrom(addr, address(this), amountToSweep);
    usdc.approve(address(tokenMessenger), amountToSweep);

    tokenMessenger.depositForBurn({
      amount: amountToSweep,
      destinationDomain: destinationDomain,
      mintRecipient: CctpTransfers.addressToBytes32(addr),
      burnToken: address(usdc)
    });

    emit Swept(addr, amountToSweep);
  }
}

