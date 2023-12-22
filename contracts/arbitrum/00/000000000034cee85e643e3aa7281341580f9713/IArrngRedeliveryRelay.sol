// SPDX-License-Identifier: MIT

/**
 *
 * @title IArrngRedeliveryRelay.sol. Interface for relaying redelivery requests.
 *
 * @author arrng https://arrng.io/
 * @author omnus https://omn.us/
 *
 */

pragma solidity 0.8.19;

interface IArrngRedeliveryRelay {
  event ArrngRedeliveryRequest(
    uint64 requestId,
    address caller,
    uint96 value,
    address refundAddress
  );

  event OracleAddressSet(address oracle);

  /**
   *
   * @dev setOracleAddress: set a new oracle address
   *
   * @param oracle_: the new oracle address
   *
   */
  function setOracleAddress(address payable oracle_) external;

  /**
   *
   * @dev requestRedelivery: request redelivery of rng. Note that this will
   * ONLY succeed if the original delivery was not sucessful (e.g. when
   * requested with insufficient native token for gas).
   *
   * The use of this method will have the following outcomes:
   * - Original delivery was SUCCESS: no redelivery, excess native token refunded to the
   * provided refund address
   * - There was no original delivery (request ID not found): no redelivery,
   * excess ETH refunded to the provided refund address
   * - There was a request and it failed: redelivery of rng as per original
   * request IF there is sufficient native token on this call. Otherwise, refund
   * of excess native token.
   *
   * requestRedelivery is overloaded. In this instance you can
   * call it without explicitly declaring a refund address, with the
   * refund being paid to the tx.origin for this call.
   *
   * @param arrngRequestId_: the Id of the original request
   *
   */
  function requestRedelivery(uint256 arrngRequestId_) external payable;

  /**
   *
   * @dev requestRedelivery: request redelivery of rng. Note that this will
   * ONLY succeed if the original delivery was not sucessful (e.g. when
   * requested with insufficient native token for gas).
   *
   * The use of this method will have the following outcomes:
   * - Original delivery was SUCCESS: no redelivery, excess native token refunded to the
   * provided refund address
   * - There was no original delivery (request ID not found): no redelivery,
   * excess ETH refunded to the provided refund address
   * - There was a request and it failed: redelivery of rng as per original
   * request IF there is sufficient native token on this call. Otherwise, refund
   * of excess native token.
   *
   * requestRedelivery is overloaded. In this instance you must
   * specify the refund address for unused native token.
   *
   * @param arrngRequestId_: the Id of the original request
   * @param refundAddress_: the address for refund of ununsed native token
   *
   */
  function requestRedelivery(
    uint256 arrngRequestId_,
    address refundAddress_
  ) external payable;
}

