// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./AviveNFTBase.sol";
import "./ProfileNFTStorage.sol";
import "./DataTypes.sol";

import "./IProfileNFTEvents.sol";

contract ProfileNFT is AviveNFTBase, ProfileNFTStorage, IProfileNFTEvents {
  function version() external pure virtual returns (uint256) {
    return PROFILE_VERSION;
  }

  function initialize(
    address verifier_,
    string calldata baseuri_
  ) public initializer {
    AviveNFTBase.__AviveNFTBase__init(baseuri_, "Avive Profile NFT", "Profile");
    verifier = verifier_;
  }

  function setVerifier(address verifier_) external onlyOwner {
    address oldVerifier = verifier;
    verifier = verifier_;

    emit LogVerifierChanged(verifier_, oldVerifier);
  }

  function createProfile(
    DataTypes.CreateProfileParams calldata params,
    bytes calldata signature
  ) external payable nonReentrant returns (uint256) {
    return _createProfile(params, signature);
  }

  function getProfile(
    uint256 id
  ) external view returns (DataTypes.Profile memory) {
    require(_exists(id), "not exist");
    return _profileRecords[id];
  }

  function getProfileIDByHandle(
    string calldata handle
  ) external view returns (uint256) {
    bytes32 handle_hash = keccak256(abi.encode(handle));
    return _handleRecords[handle_hash];
  }

  function getMintHistory(address wallet) external view returns (uint256) {
    return _mintWalletHistory[wallet];
  }

  function _createProfile(
    DataTypes.CreateProfileParams calldata params,
    bytes calldata signature
  ) internal returns (uint256) {
    require(
      _verifyProfileMintSignature(params, signature),
      "invalid signature"
    );
    require(params.expireTime > block.timestamp, "expired");
    require(_mintWalletHistory[_msgSender()] == 0, "already minted");

    bytes32 handle_hash = keccak256(abi.encode(params.handle));

    require(_handleRecords[handle_hash] == 0, "handle already exists");
    require(msg.value >= params.fee, "wrong fee");

    _safeMint(_msgSender(), params.id);

    _mintWalletHistory[_msgSender()] = params.id;
    _handleRecords[handle_hash] = params.id;
    _profileRecords[params.id] = DataTypes.Profile(params.handle);

    emit LogProfileMinted(_msgSender(), params.id, params.handle);

    return params.id;
  }

  function _verifyProfileMintSignature(
    DataTypes.CreateProfileParams calldata params,
    bytes calldata signature
  ) internal view returns (bool) {
    bytes32 message = ECDSAUpgradeable.toEthSignedMessageHash(
      keccak256(
        abi.encodePacked(
          params.id,
          params.fee,
          params.expireTime,
          params.handle,
          verifier
        )
      )
    );
    require(
      ECDSAUpgradeable.recover(message, signature) == verifier,
      "!INVALID_SIGNATURE!"
    );
    return true;
  }
}

