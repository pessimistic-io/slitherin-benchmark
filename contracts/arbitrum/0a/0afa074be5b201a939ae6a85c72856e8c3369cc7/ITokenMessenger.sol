// SPDX-License-Identifier: MIT

pragma solidity >=0.8.21;

/**
 * @title (Partial) Interface to Circle's TokenMessenger contract
 * @notice See https://github.com/circlefin/evm-cctp-contracts/tree/master for full definitions and
 *  https://developers.circle.com/stablecoins/docs/cctp-technical-reference#domain for list of valid
 *  destination domains.
 */
interface ITokenMessenger {
  /**
   * @notice Deposits and burns tokens from sender to be minted on destination domain.
   * Emits a `DepositForBurn` event.
   * @dev reverts if:
   * - given burnToken is not supported
   * - given destinationDomain has no TokenMessenger registered
   * - transferFrom() reverts. For example, if sender's burnToken balance or approved allowance
   * to this contract is less than `amount`.
   * - burn() reverts. For example, if `amount` is 0.
   * - MessageTransmitter returns false or reverts.
   * @param amount amount of tokens to burn
   * @param destinationDomain destination domain
   * @param mintRecipient address of mint recipient on destination domain
   * @param burnToken address of contract to burn deposited tokens, on local domain
   * @return _nonce unique nonce reserved by message
   */
  function depositForBurn(
    uint256 amount,
    uint32 destinationDomain,
    bytes32 mintRecipient,
    address burnToken
  ) external returns (uint64 _nonce);
}

