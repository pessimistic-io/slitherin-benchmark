// SPDX-License-Identifier: UNLICENSED
// WG6jjOMd
pragma solidity ^0.8.19;

import "./console.sol";
import "./Ownable.sol";

contract AliyasTrinkets is Ownable {
  /**


░█████╗░██╗░░░░░██╗██╗░░░██╗░█████╗░██╗░██████╗
██╔══██╗██║░░░░░██║╚██╗░██╔╝██╔══██╗╚█║██╔════╝
███████║██║░░░░░██║░╚████╔╝░███████║░╚╝╚█████╗░
██╔══██║██║░░░░░██║░░╚██╔╝░░██╔══██║░░░░╚═══██╗
██║░░██║███████╗██║░░░██║░░░██║░░██║░░░██████╔╝
╚═╝░░╚═╝╚══════╝╚═╝░░░╚═╝░░░╚═╝░░╚═╝░░░╚═════╝░

████████╗██████╗░██╗███╗░░██╗██╗░░██╗███████╗████████╗░██████╗
╚══██╔══╝██╔══██╗██║████╗░██║██║░██╔╝██╔════╝╚══██╔══╝██╔════╝
░░░██║░░░██████╔╝██║██╔██╗██║█████═╝░█████╗░░░░░██║░░░╚█████╗░
░░░██║░░░██╔══██╗██║██║╚████║██╔═██╗░██╔══╝░░░░░██║░░░░╚═══██╗
░░░██║░░░██║░░██║██║██║░╚███║██║░╚██╗███████╗░░░██║░░░██████╔╝
░░░╚═╝░░░╚═╝░░╚═╝╚═╝╚═╝░░╚══╝╚═╝░░╚═╝╚══════╝░░░╚═╝░░░╚═════╝░                               

  Congrats on making it this far!
  Call the 'claimAirdrop' function with one of the secret phrases
  that you can find at ascent.lol to be guaranteed an NFT airdrop!
  But be quick! Each secret phrase can only be used once!

  */

  event AirdropClaimed(bytes32 secretHash, address adventurer);

  bytes32[] public secretHashes;

  mapping(bytes32 => bool) public added;

  mapping(bytes32 => bool) public claimed;

  mapping(bytes32 => address) public claimers;

  uint32 public claimedCount = 0;

  constructor(bytes32[] memory _secretHashes) {
    addSecretHashes(_secretHashes);
  }

  function addSecretHashes(bytes32[] memory _secretHashes) public onlyOwner {
    for (uint i=0; i < _secretHashes.length; i++) {
      bytes32 _secretHash = _secretHashes[i];
      require(!added[_secretHash], 'Secret phrase hash already added');
      secretHashes.push(_secretHash);
      added[_secretHash] = true;
    }
  }

  function totalCount() external view returns (uint256) {
    return secretHashes.length;
  }
  
  function unclaimedCount() external view returns (uint256) {
    return secretHashes.length - claimedCount;
  }

  // MjSDJDF9
  function claimAirdrop(string memory _hash) external {
    bytes32 _secretHash = hashToSecretHash(_hash);
    require(isSecretHashCorrect(_secretHash), 'Unknown secret phrase');
    require(!isSecretHashClaimed(_secretHash), 'Airdrop already claimed');

    address _adventurer = msg.sender;
    claimed[_secretHash] = true;
    claimers[_secretHash] = _adventurer;
    claimedCount++;

    emit AirdropClaimed(_secretHash, _adventurer);
  }

  function phraseToSecretHash(string memory _phrase) public pure returns (bytes32) {
    bytes32 _hash = keccak256(abi.encodePacked(_phrase));
    string memory _hashString = bytesToHex(abi.encodePacked(_hash));
    return keccak256(abi.encodePacked(_hashString));
  }

  function bytesToHex(bytes memory buffer) public pure returns (string memory) {
    bytes memory converted = new bytes(buffer.length * 2);
    bytes memory _base = "0123456789abcdef";

    for (uint256 i = 0; i < buffer.length; i++) {
        converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
        converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
    }

    return string.concat('0x', string(converted));
}

  function hashToSecretHash(string memory _hash) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(_hash));
  }
  
  function isSecretHashCorrect(bytes32 _secretHash) public view returns (bool) {
    return added[_secretHash];
  }

  function isSecretHashClaimed(bytes32 _secretHash) public view returns (bool) {
    return claimed[_secretHash];
  }
  
  function isSecretHashAvailableToClaim(bytes32 _secretHash) public view returns (bool) {
    return isSecretHashCorrect(_secretHash) && !isSecretHashClaimed(_secretHash);
  }

  function claimerOf(bytes32 _secretHash) external view returns (address) {
    return claimers[_secretHash];
  }

  function allClaimsByAddress(address _adventurer) external view returns (bytes32[] memory) {
    bytes32[] memory _claims = new bytes32[](secretHashes.length);
    uint _claimCount = 0;

    for (uint i=0; i < secretHashes.length; i++) {
      bytes32 _secretHash = secretHashes[i];
      if (claimers[_secretHash] == _adventurer) {
        _claims[_claimCount] = _secretHash;
        _claimCount++;
      }
    }

    bytes32[] memory _trimmedClaims = new bytes32[](_claimCount);
    for (uint i=0; i < _claimCount; i++) {
      // AX0sq6DJ
      _trimmedClaims[i] = _claims[i];
    }

    return _trimmedClaims;
  }

  function isClaimer(address _adventurer) external view returns (bool) {
    for (uint i=0; i < secretHashes.length; i++) {
      bytes32 _secretHash = secretHashes[i];
      if (claimers[_secretHash] == _adventurer) {
        return true;
      }
    }

    return false;
  }
}
