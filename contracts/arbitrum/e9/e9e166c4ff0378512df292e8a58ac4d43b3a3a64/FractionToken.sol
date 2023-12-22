// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

import {NonReentrant} from "./NonReentrant.sol";
import {StrictERC20H} from "./StrictERC20H.sol";

import {ERC20} from "./ERC20.sol";
import {HolographERC20Interface} from "./HolographERC20Interface.sol";
import {HolographInterface} from "./HolographInterface.sol";
import {HolographerInterface} from "./HolographerInterface.sol";

/**
 * @title Holograph token (aka hToken), used to wrap and bridge native tokens across blockchains.
 * @author Holograph Foundation
 * @notice A smart contract for minting and managing Holograph's Bridgeable ERC20 Tokens.
 * @dev The entire logic and functionality of the smart contract is self-contained.
 */
contract FractionToken is NonReentrant, StrictERC20H {
  /**
   * @dev Fee charged on collateral for burning
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.burnFeeBp')) - 1)
   */
  bytes32 constant _burnFeeBpSlot = 0xa4d976174109ff73d791d1f3c56517b800ac914abf17db5851eabd908186e107; // 10000 == 100.00%
  /**
   * @dev Address of ERC20 token that is used as 1:1 token collateral
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.collateral')) - 1)
   */
  bytes32 constant _collateralSlot = 0x7b9af568f431a0130c2ee577a0b1187780519837e50c30c5e304078e39f01572;
  /**
   * @dev Number of decimal places for ERC20 collateral token (computed on insert)
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.collateralDecimals')) - 1)
   */
  bytes32 constant _collateralDecimalsSlot = 0x3bbd0b7b7d73273bdd8a6e80177d56c44be907ef6c71a83994b9a3adba6a25ae;
  /**
   * @dev Mapping (address => bool) of operators approved for token transfer
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.approvedOperators')) - 1)
   */
  bytes32 constant _approvedOperatorsSlot = 0x19f089e7ba2763a1f77aaa09f0e6591050763f6d19e0111fd640641e9cd72c1e;

  /**
   * @dev Constructor is left empty and init is used instead
   */
  constructor() {}

  /**
   * @notice Used internally to initialize the contract instead of through a constructor
   * @dev This function is called by the deployer/factory when creating a contract
   * @param initPayload abi encoded payload to use for contract initilaization
   */
  function init(bytes memory initPayload) external override returns (bytes4) {
    (uint256 burnFeeBp, address fractionTreasury) = abi.decode(initPayload, (uint256, address));
    assembly {
      sstore(_burnFeeBpSlot, burnFeeBp)
      sstore(_ownerSlot, fractionTreasury)
    }
    // run underlying initializer logic
    return _init(initPayload);
  }

  function mint(address recipient, uint256 amount) external nonReentrant {
    ERC20 collateral = _collateral();
    address _holographer = holographer();
    uint256 decimals = _collateralDecimals();
    // adjust decimal to fit collateral
    uint256 collateralAmount = decimals == 18 ? amount : amount / (10 ** (18 - decimals));
    if (decimals != 18) {
      // handle rounding errors by removing any amounts over the collateral decimal places
      amount = collateralAmount * (10 ** (18 - decimals));
    }
    // check collateral allowance for transfer
    require(collateral.allowance(msgSender(), _holographer) >= collateralAmount, "FRACT10N: ERC20 allowance too low");
    // store current balance in memory
    uint256 currentBalance = collateral.balanceOf(_holographer);
    // transfer collateral to token contract
    collateral.transferFrom(msgSender(), _holographer, collateralAmount);
    // check that balance is accurate
    require(
      collateral.balanceOf(_holographer) == (currentBalance + collateralAmount),
      "FRACT10N: ERC20 transfer failed"
    );
    // set recipient to msg sender if empty
    if (recipient == address(0)) {
      recipient = msgSender();
    }
    // mint the token to recipient
    HolographERC20Interface(_holographer).sourceMint(recipient, amount);
  }

  function burn(address collateralRecipient, uint256 amount) public nonReentrant {
    ERC20 collateral = _collateral();
    address _holographer = holographer();
    uint256 decimals = _collateralDecimals();
    address sender = msgSender();
    uint256 burnFee = _burnFeeBp();
    address treasury = _fractionTreasury();
    uint256 treasuryFee = 0;
    // adjust decimal to fit collateral
    uint256 collateralAmount = decimals == 18 ? amount : amount / (10 ** (18 - decimals));
    if (decimals != 18) {
      // handle rounding errors by removing any amounts over the collateral decimal places
      amount = collateralAmount * (10 ** (18 - decimals));
    }
    // store current balance in memory
    uint256 currentBalance = collateral.balanceOf(_holographer);
    // check that enough collateral is in balance
    require(currentBalance >= collateralAmount, "FRACT10N: not enough collateral");
    // burn the token from msg sender
    HolographERC20Interface(_holographer).sourceBurn(sender, amount);
    // check if caller is not Fraction Treasury
    if (sender != treasury && burnFee > 0) {
      // calculate burn fee
      treasuryFee = (collateralAmount * burnFee) / 10000;
      // apply burn fee
      collateralAmount -= treasuryFee;
      // transfer collateral burn fee to Fraction Treasury
      collateral.transferFrom(_holographer, treasury, treasuryFee);
    }
    // set recipient to msg sender if empty
    if (collateralRecipient == address(0)) {
      collateralRecipient = sender;
    }
    // transfer collateral to collateral recipient
    collateral.transferFrom(_holographer, collateralRecipient, collateralAmount);
    // check that balance is accurate
    require(
      collateral.balanceOf(_holographer) == (currentBalance - (collateralAmount + treasuryFee)),
      "FRACT10N: ERC20 transfer failed"
    );
  }

  function bridgeIn(
    uint32 /* _chainId*/,
    address from,
    address to,
    uint256 amount,
    bytes calldata /* _data*/
  ) external override onlyHolographer returns (bool success) {
    address _holographer = holographer();
    // mint the token to original from address
    HolographERC20Interface(_holographer).sourceMint(from, amount);
    if (from != to) {
      // transfer token from address to address only if they are different
      HolographERC20Interface(_holographer).sourceTransfer(from, to, amount);
    }
    success = true;
  }

  function bridgeOut(
    uint32 /* _chainId*/,
    address /* _from*/,
    address /* _to*/,
    uint256 amount
  ) external override onlyHolographer returns (bytes memory _data) {
    ERC20 collateral = _collateral();
    address _holographer = holographer();
    uint256 decimals = _collateralDecimals();
    // adjust decimal to fit collateral
    uint256 collateralAmount = decimals == 18 ? amount : amount / (10 ** (18 - decimals));
    // store current balance in memory
    uint256 currentBalance = collateral.balanceOf(_holographer);
    if (currentBalance < collateralAmount) {
      // adjust collateral amount if less than total balance/supply of token
      collateralAmount = currentBalance;
    }
    collateral.transferFrom(_holographer, _fractionTreasury(), collateralAmount);
    // check that balance is accurate
    require(
      collateral.balanceOf(_holographer) == (currentBalance - collateralAmount),
      "FRACT10N: ERC20 transfer failed"
    );
    _data = "";
  }

  function afterBurn(
    address collateralRecipient,
    uint256 amount
  ) external override onlyHolographer nonReentrant returns (bool success) {
    ERC20 collateral = _collateral();
    address _holographer = holographer();
    uint256 decimals = _collateralDecimals();
    address sender = msgSender();
    uint256 burnFee = _burnFeeBp();
    address treasury = _fractionTreasury();
    uint256 treasuryFee = 0;
    // adjust decimal to fit collateral
    uint256 collateralAmount = decimals == 18 ? amount : amount / (10 ** (18 - decimals));
    if (decimals != 18) {
      // handle rounding errors by removing any amounts over the collateral decimal places
      amount = collateralAmount * (10 ** (18 - decimals));
    }
    // store current balance in memory
    uint256 currentBalance = collateral.balanceOf(_holographer);
    // check that enough collateral is in balance
    require(currentBalance >= collateralAmount, "FRACT10N: not enough collateral");
    // check if caller is not Fraction Treasury
    if (sender != treasury && burnFee > 0) {
      // calculate burn fee
      treasuryFee = (collateralAmount * burnFee) / 10000;
      // apply burn fee
      collateralAmount -= treasuryFee;
      // transfer collateral burn fee to Fraction Treasury
      collateral.transferFrom(_holographer, treasury, treasuryFee);
    }
    // set recipient to msg sender if empty
    if (collateralRecipient == address(0)) {
      collateralRecipient = sender;
    }
    // transfer collateral to collateral recipient
    collateral.transferFrom(_holographer, collateralRecipient, collateralAmount);
    // check that balance is accurate
    require(
      collateral.balanceOf(_holographer) == (currentBalance - (collateralAmount + treasuryFee)),
      "FRACT10N: ERC20 transfer failed"
    );
    success = true;
  }

  function onAllowance(
    address account,
    address operator,
    uint256
  ) external view override onlyHolographer returns (bool success) {
    if (account == _fractionTreasury()) {
      success = false;
    } else {
      success = _approvedOperator(operator);
    }
  }

  function isApprovedOperator(address operator) external view onlyHolographer returns (bool approved) {
    approved = _approvedOperator(operator);
  }

  function getBurnFeeBp() external view returns (uint256 burnFeeBp) {
    burnFeeBp = _burnFeeBp();
  }

  function getCollateral() external view returns (address collateral) {
    collateral = address(_collateral());
  }

  function setApproveOperator(address operator, bool approved) external onlyOwner {
    assembly {
      // load next free memory
      let ptr := mload(0x40)
      // update memory pointer to increment by 64 bytes
      mstore(0x40, add(ptr, 0x40))
      // we are simulating abi.encode
      // add operator in first 32 bytes
      mstore(ptr, operator)
      // add storage slot in next 32 bytes
      mstore(add(ptr, 0x20), _approvedOperatorsSlot)
      // store mapping value to calculated storage slot
      sstore(keccak256(ptr, 0x40), approved)
    }
  }

  function setBurnFeeBp(uint256 burnFeeBp) external onlyOwner {
    require(burnFeeBp < 10001, "FRACT10N: burn fee not bp");
    assembly {
      sstore(_burnFeeBpSlot, burnFeeBp)
    }
  }

  function setCollateral(address collateralAddress) external onlyOwner {
    address collateral;
    assembly {
      collateral := sload(_collateralSlot)
    }
    require(collateral == address(0), "FRACT10N: collateral already set");
    // get collateral address decimals
    uint256 decimals = HolographERC20Interface(collateralAddress).decimals();
    // limit to 18 decimals
    require(decimals < 19, "FRACT10N: maximum 18 decimals");
    assembly {
      sstore(_collateralSlot, collateralAddress)
      sstore(_collateralDecimalsSlot, decimals)
    }
    // use Holographer to enable ERC20 transfers by source
    HolographERC20Interface(holographer()).sourceExternalCall(
      collateralAddress,
      abi.encodeWithSelector(ERC20.approve.selector, address(this), type(uint256).max)
    );
  }

  function _approvedOperator(address operator) internal view returns (bool approved) {
    assembly {
      // load next free memory
      let ptr := mload(0x40)
      // update memory pointer to increment by 64 bytes
      mstore(0x40, add(ptr, 0x40))
      // we are simulating abi.encode
      // add operator in first 32 bytes
      mstore(ptr, operator)
      // add storage slot in next 32 bytes
      mstore(add(ptr, 0x20), _approvedOperatorsSlot)
      // load mapping value from calculated storage slot
      approved := sload(keccak256(ptr, 0x40))
    }
  }

  function _burnFeeBp() internal view returns (uint256 burnFeeBp) {
    assembly {
      burnFeeBp := sload(_burnFeeBpSlot)
    }
  }

  function _collateral() internal view returns (ERC20 collateral) {
    assembly {
      collateral := sload(_collateralSlot)
    }
    require(address(collateral) != address(0), "FRACT10N: collateral not set");
  }

  function _collateralDecimals() internal view returns (uint256 decimals) {
    assembly {
      decimals := sload(_collateralDecimalsSlot)
    }
  }

  function _fractionTreasury() internal view returns (address fractionTreasury) {
    assembly {
      fractionTreasury := sload(0x1136b6b83da8d61ba4fa1d68b5ef128602c708583193e4c55add5660847fff03)
    }
  }
}

