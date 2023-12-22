// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./Ownable.sol";
import "./IAsset.sol";
import "./TimeChecker.sol";
import "./HasSignature.sol";

contract UserMinterFactory is Ownable, TimeChecker, HasSignature {
  mapping(address => bool) public tokenSupported;

  address public executor;

  event TokenMinted(
    address indexed nftAddress,
    address indexed to,
    uint256 indexed nonce,
    uint256 startTime,
    uint256[] ids
  );

  /**
   * @dev mint nft by user
   */
  function mintNft(
    address nftAddress,
    uint256[] memory tokenIds,
    uint256 startTime,
    uint256 saltNonce,
    bytes calldata signature
  ) external signatureValid(signature) timeValid(startTime) {
    require(tokenSupported[nftAddress], "UserMinterFactory: Unsupported NFT");
    address to = _msgSender();
    bytes32 criteriaMessageHash = getMessageHash(
      to,
      nftAddress,
      startTime,
      saltNonce,
      tokenIds
    );
    checkSigner(executor, criteriaMessageHash, signature);
    IAsset(nftAddress).batchMint(to, tokenIds);
    _useSignature(signature);
    emit TokenMinted(nftAddress, to, saltNonce, startTime, tokenIds);
  }

  function addTokenSupport(address nftToken) external onlyOwner {
    tokenSupported[nftToken] = true;
  }

  function removeTokenSupport(address nftToken) external onlyOwner {
    tokenSupported[nftToken] = false;
  }

  /**
   * @dev update executor
   */
  function updateExecutor(address account) external onlyOwner {
    require(account != address(0), "address can not be zero");
    executor = account;
  }

  function getMessageHash(
    address _to,
    address _nftAddress,
    uint256 _startTime,
    uint256 _saltNonce,
    uint256[] memory _ids
  ) public pure returns (bytes32) {
    bytes memory encoded = abi.encodePacked(
      _to,
      _nftAddress,
      _startTime,
      _saltNonce
    );
    uint256 len = _ids.length;
    for (uint256 i = 0; i < len; ++i) {
      encoded = bytes.concat(encoded, abi.encodePacked(_ids[i]));
    }
    return keccak256(encoded);
  }
}

