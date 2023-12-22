// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 * @title Errors library
 * @author SyntheX
 * @notice Defines the error messages emitted by the different contracts of SyntheX
 */
library Errors {
  string public constant CALLER_NOT_L0_ADMIN = '1'; // 'The caller of the function is not a pool admin'
  string public constant CALLER_NOT_L1_ADMIN = '2'; // 'The caller of the function is not an emergency admin'
  string public constant CALLER_NOT_L2_ADMIN = '3'; // 'The caller of the function is not a pool or emergency admin'
  string public constant ASSET_NOT_ENABLED = '4'; // 'The collateral is not enabled
  string public constant ACCOUNT_ALREADY_ENTERED = '5'; // 'The account has already entered the collateral
  string public constant INSUFFICIENT_COLLATERAL = '6'; // 'The account has insufficient collateral
  string public constant ZERO_AMOUNT = '7'; // 'The amount is zero
  string public constant EXCEEDED_MAX_CAPACITY = '8'; // 'The amount exceeds the maximum capacity
  string public constant INSUFFICIENT_BALANCE = '9'; // 'The account has insufficient balance
  string public constant ASSET_NOT_ACTIVE = '10'; // 'The synth is not enabled
  string public constant ASSET_NOT_FOUND = '11'; // 'The synth is not enabled
  string public constant INSUFFICIENT_DEBT = '12'; // 'The account has insufficient debt'
  string public constant INVALID_ARGUMENT = '13'; // 'The argument is invalid'
  string public constant ASSET_ALREADY_ADDED = '14'; // 'The asset is already added'
  string public constant NOT_AUTHORIZED = '15'; // 'The caller is not authorized'
  string public constant TRANSFER_FAILED = '16'; // 'The transfer failed'
  string public constant ACCOUNT_BELOW_LIQ_THRESHOLD = '17'; // 'The account is below the liquidation threshold'
  string public constant ACCOUNT_NOT_ENTERED = '18'; // 'The account has not entered the collateral'

  string public constant NOT_ENOUGH_SYX_TO_UNLOCK = '19'; // 'Not enough SYX to unlock'
  string public constant REQUEST_ALREADY_EXISTS = '20'; // 'Request already exists'
  string public constant REQUEST_DOES_NOT_EXIST = '21'; // 'Request does not exist'
  string public constant UNLOCK_NOT_STARTED = '22'; // 'Unlock not started'

  string public constant TOKEN_NOT_SUPPORTED = '23';
  string public constant ADDRESS_IS_CONTRACT = '24';
  string public constant INVALID_MERKLE_PROOF = '25';
  string public constant INVALID_TIME = '26';
  string public constant INVALID_AMOUNT = '27';
  string public constant INVALID_ADDRESS = '28';

  string public constant TIME_NOT_STARTED = '29';
  string public constant TIME_ENDED = '30';
  string public constant WITHDRAWING_MORE_THAN_ALLOWED = '31';
  string public constant ADDRESS_IS_NOT_CONTRACT = '32';

  string public constant ALREADY_SET = '33';
}
