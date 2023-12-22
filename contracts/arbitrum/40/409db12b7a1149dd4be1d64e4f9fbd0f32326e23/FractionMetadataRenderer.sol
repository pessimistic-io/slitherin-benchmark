// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import {InitializableInterface, Initializable} from "./Initializable.sol";

import {IMetadataRenderer} from "./IMetadataRenderer.sol";
import {IFractionNFT} from "./IFractionNFT.sol";
import {ERC721Metadata} from "./ERC721Metadata.sol";

import {Configuration} from "./Configuration.sol";

import {Base64} from "./Base64.sol";
import {Strings} from "./Strings.sol";

interface DropConfigGetter {
  function config() external view returns (Configuration memory config);
}

/// @notice FractionMetadataRenderer for editions support
contract FractionMetadataRenderer is Initializable, IMetadataRenderer {
  /**
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.admin')) - 1)
   */
  bytes32 constant _adminSlot = 0xce00b027a69a53c861af45595a8cf45803b5ac2b4ac1de9fc600df4275db0c38;

  /// @notice Storage for token edition information
  struct TokenEditionInfo {
    uint256 descriptionArrayIndex;
    uint256 descriptionStart;
    uint256 descriptionLength;
    uint256 imageURIArrayIndex;
    uint256 imageURIStart;
    uint256 imageURILength;
    uint256 animationURIArrayIndex;
    uint256 animationURIStart;
    uint256 animationURILength;
    bytes[] payloads;
  }

  /// @notice Event for updated Media URIs
  event MediaURIsUpdated(address indexed target, address sender, string imageURI, string animationURI);

  /// @notice Event for a new edition initialized
  /// @dev admin function indexer feedback
  event EditionInitialized(address indexed target, string description, string imageURI, string animationURI);

  /// @notice Description updated for this edition
  /// @dev admin function indexer feedback
  event DescriptionUpdated(address indexed target, address sender, string newDescription);

  /// @notice Token information mapping storage
  mapping(address => TokenEditionInfo) public tokenInfos;

  error Access_OnlyAdmin();

  /// @notice Modifier to require the sender to be an admin
  /// @param target address that the user wants to modify
  modifier requireSenderAdmin(address target) {
    if (target != msg.sender && !IFractionNFT(target).isAdmin(msg.sender)) {
      revert Access_OnlyAdmin();
    }
    _;
  }

  function init(bytes memory initPayload) external override returns (bytes4) {
    require(!_isInitialized(), "FRACT10N: already initialized");
    address fractionTreasury = abi.decode(initPayload, (address));
    assembly {
      sstore(_adminSlot, fractionTreasury)
    }
    _setInitialized();
    return InitializableInterface.init.selector;
  }

  /// @notice Default initializer for edition data from a specific contract
  /// @param data data to init with
  function initializeWithData(bytes memory data) external {
    TokenEditionInfo memory info = abi.decode(data, (TokenEditionInfo));
    address target = msg.sender;
    tokenInfos[target] = info;
    emit EditionInitialized({
      target: target,
      description: _description(target),
      imageURI: _imageURI(target),
      animationURI: _animationURI(target)
    });
  }

  /**
   * @notice Get a base64 encoded contract URI JSON string
   * @dev Used to dynamically generate contract JSON payload
   * @param name the name of the smart contract
   * @param description the name of the smart contract
   * @param imageURL string pointing to the primary contract image, can be: https, ipfs, or ar (arweave)
   * @param externalLink url to website/page related to smart contract
   * @param bps basis points used for specifying royalties percentage
   * @param contractAddress address of the smart contract
   * @return a base64 encoded json string representing the smart contract
   */
  function contractURI(
    string calldata name,
    string calldata description,
    string calldata imageURL,
    string calldata externalLink,
    uint16 bps,
    address contractAddress
  ) external pure returns (string memory) {
    return
      string(
        abi.encodePacked(
          "data:application/json;base64,",
          Base64.encode(
            abi.encodePacked(
              '{"name":"',
              name,
              '","description":"',
              description,
              '","image":"',
              imageURL,
              '","external_link":"',
              externalLink,
              '","seller_fee_basis_points":',
              Strings.uint2str(bps),
              ',"fee_recipient":"0x',
              Strings.toAsciiString(contractAddress),
              '"}'
            )
          )
        )
      );
  }

  function tokenURI(uint256 tokenId) external view returns (string memory) {
    address target = msg.sender;

    uint256 chainId = uint256(uint32(tokenId >> 224));
    bytes memory tokenAscii = abi.encodePacked(
      _uint2bytes(uint256(uint32(tokenId >> 224))),
      chainId == 0 ? "" : ":",
      _uint2bytes(uint224(tokenId))
    );

    bytes[] storage payloads = tokenInfos[target].payloads;
    bytes memory json = "";
    uint256 length = payloads.length;
    uint256 stop = length - 1;
    for (uint256 i = 0; i < length; i++) {
      json = abi.encodePacked(json, payloads[i]);
      if (i < stop) {
        json = abi.encodePacked(json, tokenAscii);
      }
    }
    return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
  }

  function _description(address target) internal view returns (string memory) {
    TokenEditionInfo storage tokenEditionInfo = tokenInfos[target];
    return
      string(
        _slice(
          tokenEditionInfo.payloads[tokenEditionInfo.descriptionArrayIndex],
          tokenEditionInfo.descriptionStart,
          tokenEditionInfo.descriptionLength
        )
      );
  }

  function _imageURI(address target) internal view returns (string memory) {
    TokenEditionInfo storage tokenEditionInfo = tokenInfos[target];
    return
      string(
        _slice(
          tokenEditionInfo.payloads[tokenEditionInfo.imageURIArrayIndex],
          tokenEditionInfo.imageURIStart,
          tokenEditionInfo.imageURILength
        )
      );
  }

  function _animationURI(address target) internal view returns (string memory) {
    TokenEditionInfo storage tokenEditionInfo = tokenInfos[target];
    return
      string(
        _slice(
          tokenEditionInfo.payloads[tokenEditionInfo.animationURIArrayIndex],
          tokenEditionInfo.animationURIStart,
          tokenEditionInfo.animationURILength
        )
      );
  }

  function _uint2bytes(uint256 _i) internal pure returns (bytes memory _uint256AsString) {
    if (_i == 0) {
      return "";
    }
    uint256 j = _i;
    uint256 len;
    while (j != 0) {
      len++;
      j /= 10;
    }
    bytes memory bstr = new bytes(len);
    uint256 k = len;
    while (_i != 0) {
      k = k - 1;
      uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
      bytes1 b1 = bytes1(temp);
      bstr[k] = b1;
      _i /= 10;
    }
    return bstr;
  }

  function _slice(bytes memory _bytes, uint256 _start, uint256 _length) internal pure returns (bytes memory) {
    require(_length + 31 >= _length, "slice_overflow");
    require(_bytes.length >= _start + _length, "slice_outOfBounds");
    bytes memory tempBytes;
    assembly {
      switch iszero(_length)
      case 0 {
        tempBytes := mload(0x40)
        let lengthmod := and(_length, 31)
        let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
        let end := add(mc, _length)
        for {
          let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
        } lt(mc, end) {
          mc := add(mc, 0x20)
          cc := add(cc, 0x20)
        } {
          mstore(mc, mload(cc))
        }
        mstore(tempBytes, _length)
        mstore(0x40, and(add(mc, 31), not(31)))
      }
      default {
        tempBytes := mload(0x40)
        mstore(tempBytes, 0)
        mstore(0x40, add(tempBytes, 0x20))
      }
    }
    return tempBytes;
  }
}

