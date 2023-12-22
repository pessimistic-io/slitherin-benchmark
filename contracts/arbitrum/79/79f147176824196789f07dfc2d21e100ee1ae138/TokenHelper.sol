// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.17;

import "./IERC20.sol";
import "./IERC721.sol";
import "./IERC1155.sol";
import "./MerkleProof.sol";
import "./ITokenStatusOracle.sol";

enum TokenStandard { ERC20, ERC721, ERC1155, ETH }

struct Token {
  TokenStandard standard;
  address addr;
  bytes32 idsMerkleRoot;
  uint id;
  bool disallowFlagged;
}

struct IdsProof {
  uint[] ids;
  bytes32[] merkleProof_hashes;
  bool[] merkleProof_flags;
  uint[] statusProof_lastTransferTimes;
  uint[] statusProof_timestamps;
  bytes[] statusProof_signatures;
}

error UnsupportedTokenStandard();
error IdNotAllowed();
error AtLeastOneIdRequired();
error MerkleProofsRequired();
error ERC1155IdNotProvided();
error OwnerHasNft();
error InvalidIds();
error IdMismatch();
error IdsLengthZero();
error DuplicateIds();
error InvalidMerkleProof();

contract TokenHelper {

  ITokenStatusOracle private constant TOKEN_STATUS_ORACLE = ITokenStatusOracle(0x3403bbfefe9cc0DDAA801D4d89F74FB838148E2E);

  function transferFrom (address tokenAddress, TokenStandard tokenStandard, address from, address to, uint amount, uint[] memory ids) internal {
    if (tokenStandard == TokenStandard.ERC20) {
      IERC20(tokenAddress).transferFrom(from, to, amount);
      return;
    }
    
    if (tokenStandard == TokenStandard.ERC721) {
      if (ids.length == 0) {
        revert IdsLengthZero();
      }
      for (uint8 i=0; i < ids.length; i++) {
        IERC721(tokenAddress).transferFrom(from, to, ids[i]);
      }
      return;
    } else if (tokenStandard == TokenStandard.ERC1155) {
      if (ids.length == 1) {
        IERC1155(tokenAddress).safeTransferFrom(from, to, ids[0], amount, '');
      } else if (ids.length > 1) {
        // for ERC1155 transfers with multiple id's provided, transfer 1 per id
        uint[] memory amounts = new uint[](ids.length);
        for (uint8 i=0; i < ids.length; i++) {
          amounts[i] = 1;
        }
        IERC1155(tokenAddress).safeBatchTransferFrom(from, to, ids, amounts, '');
      } else {
        revert IdsLengthZero();
      }
      return;
    }

    revert UnsupportedTokenStandard();
  }

  // returns
  //    balance: total balance for all ids
  //    ownedIdCount: total number of ids with balance > 0
  //    idBalances: array of individual id balances
  function tokenOwnership (
    address owner,
    TokenStandard tokenStandard,
    address tokenAddress,
    uint[] memory ids
  ) internal view returns (uint balance, uint ownedIdCount, uint[] memory idBalances) {
    if (tokenStandard == TokenStandard.ERC721 || tokenStandard == TokenStandard.ERC1155) {
      if (ids[0] == 0) {
        revert AtLeastOneIdRequired();
      }

      idBalances = new uint[](ids.length);

      for (uint8 i=0; i<ids.length; i++) {
        if (tokenStandard == TokenStandard.ERC721 && IERC721(tokenAddress).ownerOf(ids[i]) == owner) {
          ownedIdCount++;
          balance++;
          idBalances[i] = 1;
        } else if (tokenStandard == TokenStandard.ERC1155) {
          idBalances[i] = IERC1155(tokenAddress).balanceOf(owner, ids[i]);
          if (idBalances[i] > 0) {
            ownedIdCount++;
            balance += idBalances[i];
          }
        }
      }
    } else if (tokenStandard == TokenStandard.ERC20) {
      balance = IERC20(tokenAddress).balanceOf(owner);
    } else if (tokenStandard == TokenStandard.ETH) {
      balance = owner.balance;
    } else {
      revert UnsupportedTokenStandard();
    }
  }

  function verifyTokenIds (Token memory token, IdsProof memory idsProof) internal view {
    // if token specifies a single id, verify that one proof id is provided that matches
    if (token.id > 0 && !(idsProof.ids.length == 1 && idsProof.ids[0] == token.id)) {
      revert IdMismatch();
    }

    // if token specifies a merkle root for ids, verify merkle proofs provided for the ids
    if (
      token.idsMerkleRoot != bytes32(0) &&
      !verifyIdsMerkleProof(
        idsProof.ids,
        idsProof.merkleProof_hashes,
        idsProof.merkleProof_flags,
        token.idsMerkleRoot
      )
    ) {
      revert InvalidMerkleProof();
    }

    // if token is ERC721 or ERC1155 and does not specify a merkleRoot or Id, verify that no duplicate ids are provided
    if (
      (
        token.standard == TokenStandard.ERC721 ||
        token.standard == TokenStandard.ERC1155
      ) &&
      token.idsMerkleRoot == bytes32(0) &&
      token.id == 0 &&
      idsProof.ids.length > 1
    ) {
      for (uint8 i=0; i<idsProof.ids.length; i++) {
        for (uint8 j=i+1; j<idsProof.ids.length; j++) {
          if (idsProof.ids[i] == idsProof.ids[j]) {
            revert DuplicateIds();
          }
        }
      }
    }

    // if token has disallowFlagged=true, verify status proofs provided for the ids
    if (token.disallowFlagged) {
      verifyTokenIdsNotFlagged(
        token.addr,
        idsProof.ids,
        idsProof.statusProof_lastTransferTimes,
        idsProof.statusProof_timestamps,
        idsProof.statusProof_signatures
      );
    }
  }

  function verifyTokenIdsNotFlagged (
    address tokenAddress,
    uint[] memory ids,
    uint[] memory lastTransferTimes,
    uint[] memory timestamps,
    bytes[] memory signatures
  ) internal view {
    for(uint8 i = 0; i < ids.length; i++) {
      TOKEN_STATUS_ORACLE.verifyTokenStatus(tokenAddress, ids[i], false, lastTransferTimes[i], timestamps[i], signatures[i]);
    }
  }

  function verifyIdsMerkleProof (uint[] memory ids, bytes32[] memory proof, bool[] memory proofFlags, bytes32 root) internal pure returns (bool) {
    if (ids.length == 0) {
      return false;
    } else if (ids.length == 1) {
      return verifyId(proof, root, ids[0]);
    } else {
      return verifyIds(proof, proofFlags, root, ids);
    }
  }

  function verifyId (bytes32[] memory proof, bytes32 root, uint id) internal pure returns (bool) {
    bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(id))));
    return MerkleProof.verify(proof, root, leaf);
  }

  function verifyIds (bytes32[] memory proof, bool[] memory proofFlags, bytes32 root, uint[] memory ids) internal pure returns (bool) {
    bytes32[] memory leaves = new bytes32[](ids.length);
    for (uint8 i=0; i<ids.length; i++) {
      leaves[i] = keccak256(bytes.concat(keccak256(abi.encode(ids[i]))));
    }
    return MerkleProof.multiProofVerify(proof, proofFlags, root, leaves);
  }

}

