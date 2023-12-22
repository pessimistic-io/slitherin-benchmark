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

import "./IMintPipe.sol";
import "./IMintValidator.sol";
import "./IFabricator.sol";
import "./verification_Auth.sol";

/// @title AggregateValidator
/// @notice Basic validator allows several other validators to create tokens based on role authorities
/// @dev Plz don't use this it's not meant for you
contract AggregateValidator is IMintValidator, Auth, IMintPipe {
  uint256 private immutable _id;
  // This is the instance of core we call home to for the minty minty
  IFabricator public core;
  uint256 public totalSupply;
  uint256 public totalMinted;
  uint256 public perTxLimit;

  /// @param _core we use this to trigger the token mints
  /// @param id_ This ID must be registered in core, this is the ID that portalpills will mint into
  /// @param _supply This is the total supply of tokens that will be minted
  constructor(
    IFabricator _core,
    uint256 id_,
    uint256 _supply,
    Authority authority
  ) Auth(msg.sender, authority) {
    _id = id_;
    core = _core;
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

  /// @notice Sets a limit on the number of pills that can be purchased in a single transaction
  /// @param limit New token limit per transaction
  function newLimit(uint256 limit) external requiresAuth {
    require(limit < totalSupply, "Limit must be under supply total");
    perTxLimit = limit;
  }

  /// @notice Sets a limit on the total number of pills that can be purchased
  /// @param supply New token limit per transaction
  function newSupply(uint256 supply) external requiresAuth {
    require(supply < totalSupply, "Supply must be under supply total");
    totalSupply = supply;
  }

  function modularMintCallback(
    address recipient,
    uint256[] memory _ids,
    uint256[] memory _requestedAmounts,
    bytes memory _data
  ) external override requiresAuth {
    core.modularMintCallback(recipient, _ids, _requestedAmounts, _data);
  }
}

