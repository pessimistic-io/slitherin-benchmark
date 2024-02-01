// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./Owned.sol";
import "./IERC721.sol";
import "./ECDSA.sol";

contract SantaInvader is Owned {
  struct NFT {
    address contractAddress;
    uint256 tokenId;
  }

  uint256 public totalCount;
  address private _verifier;

  mapping(uint256 => NFT) public nfts;
  mapping(address => uint256) private _openedByWallet;

  constructor(address _initialOwner) Owned(_initialOwner) {}

  function openPresent(uint256 _count, bytes calldata _signature) external {
    address signer = _recoverWallet(msg.sender, _count, _signature);

    require(signer == _verifier, "Unverified transaction");
    require(_openedByWallet[msg.sender] < _count, "Invalid present count");

    _openedByWallet[msg.sender] = _count;

    uint256 total = totalCount--;
    uint256 index = _getPsudoRandomNumber() % total;

    uint256 tokenId = nfts[index].tokenId;
    address nftContract = nfts[index].contractAddress;

    nfts[index] = nfts[total - 1];
    delete nfts[total - 1];

    IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
  }

  function viewNFTs(uint256 _start, uint256 _maxLen)
    external
    view
    returns (NFT[] memory)
  {
    if (_start >= totalCount) return new NFT[](0);

    if (_start + _maxLen > totalCount) _maxLen = totalCount - _start;

    NFT[] memory _nfts = new NFT[](_maxLen);

    for (uint256 i = 0; i < _maxLen; i++) {
      _nfts[i] = nfts[i + _start];
    }

    return _nfts;
  }

  function _recoverWallet(
    address _wallet,
    uint256 _amount,
    bytes memory _signature
  ) internal pure returns (address) {
    return
      ECDSA.recover(
        ECDSA.toEthSignedMessageHash(
          keccak256(abi.encodePacked(_wallet, _amount))
        ),
        _signature
      );
  }

  function _getPsudoRandomNumber() internal view returns (uint256) {
    uint256 randomNumber = uint256(
      keccak256(
        abi.encodePacked(
          block.timestamp,
          block.difficulty,
          totalCount,
          msg.sender
        )
      )
    );

    return randomNumber;
  }

  function setVerifier(address _newVerifier) public onlyOwner {
    _verifier = _newVerifier;
  }

  function depositNFTs(
    address[] calldata _contracts,
    uint256[] calldata _tokenIds
  ) external onlyOwner {
    require(_contracts.length == _tokenIds.length, "Input length mismatch");

    uint256 len = _contracts.length;
    uint256 currentCount = totalCount;

    for (uint256 i = 0; i < len; i++) {
      nfts[currentCount++] = NFT(_contracts[i], _tokenIds[i]);
    }

    totalCount = currentCount;
  }

  function removeNFTs(uint256[] calldata _nfts) external onlyOwner {
    uint256 total = totalCount;

    for (uint256 i = 0; i < _nfts.length; i++) {
      address nftContract = nfts[_nfts[i]].contractAddress;
      uint256 tokenId = nfts[_nfts[i]].tokenId;

      nfts[_nfts[i]] = nfts[total - i - 1];
      delete nfts[total - i - 1];

      IERC721(nftContract).transferFrom(address(this), owner, tokenId);
    }

    totalCount -= _nfts.length;
  }
}

