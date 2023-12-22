// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;

import "./Context.sol";
import "./Strings.sol";
// Experiment with solmate 721?
import "./ERC721.sol";
import "./IMintValidator721.sol";
import "./IXferHook.sol";
import "./IFabricator721.sol";
import "./IReadMetadata.sol";

import "./Auth.sol";

/// @title Core721
/// @author The name of the author
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details//Interface
contract Core721 is Context, ERC721, IFabricator721, Auth {
  using Strings for uint256;
  event Validator(IMintValidator721 indexed validator, bool indexed active);

  mapping(IMintValidator721 => bool) public isValidator;
  mapping(uint256 => address) public override idToValidator;
  mapping(uint256 => uint256) public override quantityMinted;
  mapping(uint256 => address) public idToTransferHook;
  // URI base; NOT the whole uri.
  string private _baseURI;
  IReadMetadata private _registry;

  /**
   * @dev intializes the core ERC1155 logic, and sets the original URI base
   */
  constructor(
    string memory baseUri_,
    IReadMetadata registry_,
    Authority authority
  ) ERC721("PILLS AVATARS", "AVAPILL") Auth(msg.sender, authority) {
    _registry = registry_;
    _baseURI = baseUri_;
  }

  modifier onlyValidator() {
    bool isActive = isValidator[IMintValidator721(msg.sender)];
    require(isActive, "VALIDATOR_INACTIVE");
    _;
  }

  /**
   * @dev query URI for a token Id. Queries the Metadata registry on the backend
   */
  function uri(uint256 _id) public view returns (string memory) {
    // Use the underlying metadata contract?
    return string(abi.encodePacked(_baseURI, _id.toString()));
  }

  /**
   * @dev change the URI base address after construction.
   */
  function setBaseURI(string calldata _newBaseUri) external requiresAuth {
    _baseURI = _newBaseUri;
  }

  /**
   * @dev change the URI base address after construction.
   */
  function setNewRegistry(IReadMetadata registry_) external requiresAuth {
    _registry = registry_;
  }

  /**
   * @dev An active Validator is necessary to enable `modularMint`
   */
  function addValidator(IMintValidator721 _validator, uint256[] memory ids)
    external
    virtual
    requiresAuth
  {
    bool isActive = isValidator[_validator];
    require(!isActive, "VALIDATOR_ACTIVE");
    for (uint256 i; i < ids.length; i++) {
      require(idToValidator[ids[i]] == address(0x0), "INVALID_VALIDATOR_IDS");
      idToValidator[ids[i]] = address(_validator);
    }
    isValidator[_validator] = true;
    emit Validator(_validator, !isActive);
  }

  /**
   * @dev An active Validator is necessary to enable `modularMint`
   */
  function addTransferHook(IXferHook hooker, uint256[] memory ids)
    external
    virtual
    requiresAuth
  {
    for (uint256 i; i < ids.length; i++) {
      require(idToTransferHook[ids[i]] == address(0x0), "INVALID_HOOK_IDS");
      idToTransferHook[ids[i]] = address(hooker);
    }
  }

  /**
   * @dev Remove Validators that are no longer needed to remove attack surfaces
   */
  function removeValidator(IMintValidator721 _validator, uint256[] memory ids)
    external
    virtual
    requiresAuth
  {
    bool isActive = isValidator[_validator];
    require(isActive, "VALIDATOR_INACTIVE");
    for (uint256 i; i < ids.length; i++) {
      idToValidator[ids[i]] = address(0x0);
    }
    isValidator[_validator] = false;
    emit Validator(_validator, !isActive);
  }

  /**
   * @dev Mint mulitiple tokens at different quantities. This is an requiresAuth
          function and is meant basically as a sudo-command. Auth should be 
   */
  function mint(
    address _to,
    uint256 _id,
    bytes memory _data
  ) external virtual requiresAuth {
    _safeMint(_to, _id, _data);
  }

  /**
   * @dev Creates `amount` new tokens for `to`, of token type `id`.
   *      At least one Validator must be active in order to utilized this interface.
   */
  function modularMintInit(
    uint256 _dropId,
    address _to,
    bytes memory _data,
    address _validator,
    string calldata _metadata
  ) public virtual override {
    IMintValidator721 validator = IMintValidator721(_validator);
    require(isValidator[validator], "BAD_VALIDATOR");
    validator.validate(_to, _dropId, _metadata, _data);
  }

  /**
   * @dev Creates `amount` new tokens for `to`, of token type `id`.
   *      At least one Validator must be active in order to utilized this interface.
   */
  function modularMintCallback(
    address recipient,
    uint256 _id,
    bytes calldata _data
  ) public virtual override onlyValidator {
    require(idToValidator[_id] == address(msg.sender), "INVALID_MINT");
    _safeMint(recipient, _id, _data);
  }

  // OPTIMIZATION: No need for numbers to be readable, so this could be optimized
  // but gas cost here doesn't matter so we go for the standard approach
  function tokenURI(uint256 _id) public view override returns (string memory) {
    return string(abi.encodePacked(_baseURI, _id.toString()));
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 id
  ) internal override {
    if (idToTransferHook[id] != address(0x0)) {
      IXferHook(idToTransferHook[id]).xferHook(from, to, id);
    }
  }
}

