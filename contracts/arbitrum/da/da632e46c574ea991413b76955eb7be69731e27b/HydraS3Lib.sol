// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

struct HydraS3CircomSnarkProof {
  uint256[2] a;
  uint256[2][2] b;
  uint256[2] c;
}

struct HydraS3ProofData {
  HydraS3CircomSnarkProof proof;
  uint256[14] input;
  // destinationIdentifier;
  // extraData;
  // commitmentMapperPubKey.X;
  // commitmentMapperPubKey.Y;
  // registryTreeRoot;
  // requestIdentifier;
  // proofIdentifier;
  // claimValue;
  // accountsTreeValue;
  // claimComparator;
  // vaultIdentifier;
  // vaultNamespace;
  // sourceVerificationEnabled;
  // destinationVerificationEnabled;
}

struct HydraS3ProofInput {
  address destinationIdentifier;
  uint256 extraData;
  uint256[2] commitmentMapperPubKey;
  uint256 registryTreeRoot;
  uint256 requestIdentifier;
  uint256 proofIdentifier;
  uint256 claimValue;
  uint256 accountsTreeValue;
  uint256 claimComparator;
  uint256 vaultIdentifier;
  uint256 vaultNamespace;
  bool sourceVerificationEnabled;
  bool destinationVerificationEnabled;
}

library HydraS3Lib {
  uint256 public constant SNARK_FIELD =
    21888242871839275222246405745257275088548364400416034343698204186575808495617;

  function _input(HydraS3ProofData memory self) internal pure returns (HydraS3ProofInput memory) {
    return
      HydraS3ProofInput(
        _getDestinationIdentifier(self),
        _getExtraData(self),
        _getCommitmentMapperPubKey(self),
        _getRegistryRoot(self),
        _getRequestIdentifier(self),
        _getProofIdentifier(self),
        _getClaimValue(self),
        _getAccountsTreeValue(self),
        _getClaimComparator(self),
        _getVaultIdentifier(self),
        _getVaultNamespace(self),
        _getSourceVerificationEnabled(self),
        _getDestinationVerificationEnabled(self)
      );
  }

  function _toCircomFormat(
    HydraS3ProofData memory self
  )
    internal
    pure
    returns (uint256[2] memory, uint256[2][2] memory, uint256[2] memory, uint256[14] memory)
  {
    return (self.proof.a, self.proof.b, self.proof.c, self.input);
  }

  function _getDestinationIdentifier(HydraS3ProofData memory self) internal pure returns (address) {
    return address(uint160(self.input[0]));
  }

  function _getExtraData(HydraS3ProofData memory self) internal pure returns (uint256) {
    return self.input[1];
  }

  function _getCommitmentMapperPubKey(
    HydraS3ProofData memory self
  ) internal pure returns (uint256[2] memory) {
    return [self.input[2], self.input[3]];
  }

  function _getRegistryRoot(HydraS3ProofData memory self) internal pure returns (uint256) {
    return self.input[4];
  }

  function _getRequestIdentifier(HydraS3ProofData memory self) internal pure returns (uint256) {
    return self.input[5];
  }

  function _getProofIdentifier(HydraS3ProofData memory self) internal pure returns (uint256) {
    return self.input[6];
  }

  function _getClaimValue(HydraS3ProofData memory self) internal pure returns (uint256) {
    return self.input[7];
  }

  function _getAccountsTreeValue(HydraS3ProofData memory self) internal pure returns (uint256) {
    return self.input[8];
  }

  function _getClaimComparator(HydraS3ProofData memory self) internal pure returns (uint256) {
    return self.input[9];
  }

  function _getVaultIdentifier(HydraS3ProofData memory self) internal pure returns (uint256) {
    return self.input[10];
  }

  function _getVaultNamespace(HydraS3ProofData memory self) internal pure returns (uint256) {
    return self.input[11];
  }

  function _getSourceVerificationEnabled(
    HydraS3ProofData memory self
  ) internal pure returns (bool) {
    return self.input[12] == 1;
  }

  function _getDestinationVerificationEnabled(
    HydraS3ProofData memory self
  ) internal pure returns (bool) {
    return self.input[13] == 1;
  }
}

