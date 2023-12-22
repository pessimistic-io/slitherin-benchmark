// SPDX-License-Identifier: MIT

/**
 *
 * @title ArrngConsumer.sol. Use arrng
 *
 * @author arrng https://arrng.xyz/
 * v1.0.0
 *
 */

import {IArrngConsumer} from "./IArrngConsumer.sol";
import {IArrngController} from "./IArrngController.sol";

pragma solidity 0.8.19;

abstract contract ArrngConsumer is IArrngConsumer {
  IArrngController constant arrngController = 
    IArrngController(0x8888881FA4b02bd6A5628BB34463Cc2570888888);

  /**
   * @dev constructor
   */
  constructor() {}

  /**
   *
   * @dev fulfillRandomWords: Do something with the RNG
   *
   * @param requestId: unique ID for this request
   * @param randomWords: array of random integers requested
   *
   */
  function fulfillRandomWords(
    uint256 requestId,
    uint256[] memory randomWords
  ) internal virtual;

  /**
   *
   * @dev yarrrr: receive RNG
   *
   * @param skirmishID_: unique ID for this request
   * @param barrelONum_: array of random integers requested
   *
   */
  function yarrrr(
    uint256 skirmishID_,
    uint256[] calldata barrelONum_
  ) external payable {
    require(msg.sender == address(arrngController), "BelayThatOfficersOnly");
    fulfillRandomWords(skirmishID_, barrelONum_);
  }
}

