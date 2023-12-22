// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


interface IDeFiBridgeErrors {
  error ChainZeroErr();
  error ChainDuplicateErr();
  error ChainDisabledErr(uint16 chain);
  error ChainUndefinedErr(uint16 chain);
  
  error WormholeNullAddressErr();
  error WalletNullAddressErr();
  error RelayertNullAddressErr();
  error PoolNullAddressErr();
  error SenderNullAddressErr();
  error DefiNullAddressErr();

  error RelayertAuthErr();
  error SenderAuthErr();
  error MaxTokenFeeErr(uint256 fee);
  error MinMaxTokenFeeErr(uint256 min, uint256 max);
  error NativeFeeErr(uint256 fee, uint256 value);
  error NativeFeeTransferErr();
  error NativeRefundTransferErr();
  error NativeTransferErr();
  error MsgDuplicateErr(bytes32 hash);
}
