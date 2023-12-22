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
import "./verification_Auth.sol";

/// @title AirdropValidator
/// @notice Validator is meant to check whether or not a specific NFT is held, and then spit out a corrsponding NFT.
///         For our use case we use it to allow people with a legacy pill to receive a portalpill. Main issues we've seen so far with this
///         has been in tracking
/// @dev Plz don't use this it's not meant for you
contract AirdropValidator is Auth {
  // This is the token we "check" against. Understand that the collection you're point this to
  // has a tremendous amount of control over the token ID this checker instance is registered with in core

  // This is the instance of core we call home to for the minty minty
  IMintPipe public core;

  /// @param _core we use this to trigger the token mints
  constructor(
    IMintPipe _core,
    Authority authority
  ) Auth(msg.sender, authority) {
    core = _core;
  }

  function setCore(IMintPipe _core) public requiresAuth {
    core = _core;
  }


  // Assumes _recipient and _amounts are the same length
  function drop(address[] calldata _recipient, uint256[] calldata  _amounts, uint256 id) external requiresAuth {
    uint256[] memory idReturn = new uint256[](1);
    uint256[] memory quantityReturn = new uint256[](1);
    idReturn[0] = id;
    for (uint256 index = 0; index < _recipient.length; index++) {
      quantityReturn[0] = _amounts[index];
      core.modularMintCallback(_recipient[index], idReturn, quantityReturn, "");      
    }
  }
}

