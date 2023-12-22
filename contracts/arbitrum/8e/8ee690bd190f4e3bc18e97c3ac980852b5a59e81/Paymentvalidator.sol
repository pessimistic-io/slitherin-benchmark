// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;

//                       .,,,,.
//               ,(%%%%%%%%%%%%%%%%%%#,
//           .#%%%%%%%%%%%%%%%%%%%%%%%%%%#,
//         (%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%(.
//       (%%%%%%%%%%%%%%%%%%%%%%%#*,,*/#%%%%%%%*
//     ,%%%%%%%%%%%%%%%%%%%%%%%%/,,,,,,,,,*#%%%%%(.
//    *%%%%%%%%%%%%%%%%%%%%%%%%%/,,,,,,,,,,,,*#%%%%%*
//   ,%%%%%%%%%%%%%%%%%%%%%%%%%%%/,,,,,,,,,,,,,,/%%%%%(.
//   /%%%%%%%%%%%%%%%%%%%%%%%%%%%%#*,,,,,,,,,,,,,,*#%%%%%*
//   (%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#*,,,,,,,,,,,,,,,/%%%%%(.
//   (%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%(*,,,,,,,,,,,,,,*#%%%%%*
//   *%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%/,,,,,,,,,,,,,,,(%%%%%#.
//    (%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#*,,,,,,,,,,,,,,(%%%%%%*
//     #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%(,,,,,,,,,,,,,,*%%%&&&#.
//      *%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%/,,,,,,,,,,,,,*%&&&==&*
//        (%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#*,,,,,,,,,,,,*#&=====(.
//          *%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%(*,,,,,,,,,,,,/%=====&*
//            .(%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%&%/,,,,,,,,,,,,/%&=====#.
//               *%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%&&&&%%#*,,,,,,,,,,,*#======&*
//                 .(%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%&&&&&=====&%(,,,,,,,,,,,*#%======#.
//                    *%%%%%%%%%%%%%%%%%%%%%%%%%%&&&&&===========%/,,,,,,,,,,,(%======&*
//                      .(%%%%%%%%%%%%%%%%%%%%&&&&&================&#*,,,,,,,,,,/%=======#.
//                         *%%%%%%%%%%%%%%%&&&&&&=====================%(,,,,,,,,,,*%&======&*
//                           .(%%%%%%%%%%&&&&&==========================&%/,,,,,,,,,*%========/
//                              *%%%%%&&&&&&===============================%#*,,,,,,,,(%=======%,
//                                .(&&&&&=====================================%#*,,,,,*%&=======&,
//                                  *%==========================================&%%##%==========%,
//                                     .(=========================================================(
//                                        *%======================================================%.
//                                          .(====================================================#.
//                                             *%=================================================(
//                                               .(==============================================%.
//                                                  *%==========================================&,
//                                                    .(=======================================%.
//                                                       *%===================================*
//                                                         .(==============================%,
//                                                            .(&=======================#,
//                                                                ,(%&===========%#*

import "./IMintValidator.sol";
import "./IFabricator.sol";
import "./Ownable.sol";

/// @title PaymentValidator
/// @notice Basic validator that takes payment in ETH and mints out an mount of tokens in the initialized ID
/// @dev Plz don't use this it's not meant for you
contract PaymentValidator is IMintValidator, Ownable {
  uint256 private immutable _id;
  // This is the instance of core we call home to for the minty minty
  IFabricator public core;
  uint256 private _cost;
  uint256 public totalSupply;
  uint256 public totalMinted;
  uint256 public perTxLimit;

  /// @param _core we use this to trigger the token mints
  /// @param id_ This ID must be registered in core, this is the ID that portalpills will mint into
  /// @param cost_ Cost in WEI (ETH) required _per 1155_
  constructor(
    IFabricator _core,
    uint256 id_,
    uint256 cost_,
    uint256 _supply
  ) {
    _id = id_;
    core = _core;
    _cost = cost_;
    totalSupply = _supply;
    perTxLimit = totalSupply;
  }

  /// @notice DO NOT USE
  /// @dev prevents calls from the main core instance since this validation requires payments
  function validate(
    address,
    uint256, /* _dropId*/
    uint256[] calldata, /* _qty*/
    string calldata, /* _metadata*/
    bytes memory /* _data*/
  ) external override {
    revert("Use payable validator");
  }

  /// @notice Purchase PortalPills directly
  /// @param _recipient Target account to receieve the purchased Portal Pills
  /// @param _qty Number of PortalPills to purchase
  function directSale(address _recipient, uint256 _qty) external payable {
    uint256 newTotal;
    require(_qty <= perTxLimit, "Not enough supply");
    // Quantity + total minted will never overflow
    unchecked {
      newTotal = _qty + totalMinted;
    }
    require(newTotal <= totalSupply, "Not enough supply");
    require(msg.value / _cost >= _qty, "Sorry not enough ETH provided");
    _validate(_recipient, _qty);
    totalMinted = newTotal;
  }

  /// @notice Collects and sends an amount of ETH to the selected target from this validator
  /// @param target Address to send requested ETH to
  /// @param value Amount of ETH (in wei) to transfer
  function collectEth(address target, uint256 value) external onlyOwner {
    _sendEth(target, value);
  }

  /// @notice Sets a limit on the number of pills that can be purchased in a single transaction
  /// @param limit New token limit per transaction
  function newLimit(uint256 limit) external onlyOwner {
    require(limit < totalSupply, "Limit must be under supply total");
    perTxLimit = limit;
  }

  /// @notice Collects all ETH to the selected target from this validator
  /// @param target Address to send requested ETH to
  function collectAllEth(address target) external onlyOwner {
    _sendEth(target, address(this).balance);
  }

  function _sendEth(address target, uint256 value) internal {
    (bool success, ) = target.call{value: value}("");
    require(success, "Transfer failed.");
  }

  function _validate(address _recipient, uint256 _qty) internal {
    uint256[] memory idReturn = new uint256[](1);
    uint256[] memory quantityReturn = new uint256[](1);
    idReturn[0] = _id;
    quantityReturn[0] = _qty;
    core.modularMintCallback(_recipient, idReturn, quantityReturn, "");
  }
}

