// Neptune Mutual Protocol (https://neptunemutual.com)
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Vault.sol";

library VaultFactoryLibV1 {
  /**
   * @dev Gets the bytecode of the `Vault` contract
   * @param s Provide the store instance
   * @param coverKey Provide the cover key
   * @param stablecoin Specify the liquidity token for this Vault
   */
  function getByteCodeInternal(
    IStore s,
    bytes32 coverKey,
    string calldata tokenName,
    string calldata tokenSymbol,
    address stablecoin
  ) external pure returns (bytes memory bytecode, bytes32 salt) {
    salt = keccak256(abi.encodePacked(ProtoUtilV1.NS_CONTRACTS, ProtoUtilV1.CNS_COVER_VAULT, coverKey));

    //slither-disable-next-line too-many-digits
    bytecode = abi.encodePacked(type(Vault).creationCode, abi.encode(s, coverKey, tokenName, tokenSymbol, stablecoin));
  }
}

