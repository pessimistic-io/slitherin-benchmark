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

import "./MerkleProof.sol";
import "./tokens_ERC1155.sol";
import "./verification_Context.sol";
import "./IMintValidator.sol";
import "./IFabricator.sol";

/// @title CheckerValidator
/// @notice Validator is meant to check whether or not a specific NFT is held, and then spit out a corrsponding NFT.
///         For our use case we use it to allow people with a legacy pill to receive a portalpill. Main issues we've seen so far with this
///         has been in tracking
/// @dev Plz don't use this it's not meant for you
contract CheckerValidator is Context, IMintValidator {
  // This is the token we "check" against. Understand that the collection you're point this to
  // has a tremendous amount of control over the token ID this checker instance is registered with in core
  IERC1155 public originalToken;
  uint256 immutable _newId;
  // initialize with token and track state there
  mapping(uint256 => bool) public redeemed;
  mapping(address => uint256) public remaining;
  // This is the instance of core we call home to for the minty minty
  IFabricator public core;

  /// @param _core we use this to trigger the token mints
  /// @param _original Token whose balance we check for mints; implier 1;1 1155s plzz
  /// @param newId_ This ID must be registered in core, 1155s of the old system will
  constructor(
    IFabricator _core,
    IERC1155 _original,
    uint256 newId_
  ) {
    _newId = newId_;
    core = _core;
    originalToken = _original;
  }

  function checkAllRedemption(uint256[] calldata ids)
    external
    view
    returns (bool[] memory)
  {
    bool[] memory redemptionStatus = new bool[](ids.length);
    for (uint256 i = 0; i < redemptionStatus.length; i++) {
      redemptionStatus[i] = _checkRedemption(ids[i]);
    }
    return redemptionStatus;
  }

  function _checkRedemption(uint256 id) internal view returns (bool) {
    return redeemed[id];
  }

  function redeemAll(uint256[] calldata ids) public {
    for (uint256 i = 0; i < ids.length; i++) {
      _redeem(ids[i], _msgSender());
    }
    _validate(_msgSender());
  }

  function _redeem(uint256 id, address target) internal {
    require(
      originalToken.balanceOf(target, id) > 0,
      "Sender must hold all tokens for migration"
    );
    require(redeemed[id] == false, "Token has already been redeemed");
    redeemed[id] = true;
    remaining[target] += 1;
  }

  function validate(
    address _recipient,
    uint256, /* _dropId*/
    uint256[] calldata, /* _qty*/
    string calldata, /* _metadata*/
    bytes memory /* _data*/
  ) external override {
    _validate(_recipient);
  }

  function _validate(address _recipient) internal {
    uint256[] memory idReturn = new uint256[](1);
    uint256[] memory quantityReturn = new uint256[](1);
    idReturn[0] = _newId;
    quantityReturn[0] = remaining[_recipient];
    remaining[_recipient] = 0;
    core.modularMintCallback(_recipient, idReturn, quantityReturn, "");
  }
}

