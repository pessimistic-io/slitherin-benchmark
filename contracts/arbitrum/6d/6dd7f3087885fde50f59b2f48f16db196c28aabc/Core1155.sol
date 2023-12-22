// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;

import "./ERC1155.sol";
import "./Context.sol";
import "./Ownable.sol";
import "./IMintValidator.sol";
import "./IFabricator.sol";
import "./MetadataRegistry.sol";
import "./Auth.sol";
import "./IXferHook.sol";

// write interface for
//Interface

contract Core1155 is Context, ERC1155, Auth, IFabricator {
  event Validator(IMintValidator indexed validator, bool indexed active);

  mapping(IMintValidator => bool) public isValidator;
  mapping(uint256 => address) public override idToValidator;
  mapping(uint256 => uint256) public override quantityMinted;
  mapping(uint256 => address) public idToTransferHook;
  // URI base; NOT the whole uri.
  string private _uri;
  IReadMetadata private _registry;

  /**
   * @dev intializes the core ERC1155 logic, and sets the original URI base
   */
  constructor(
    string memory baseUri_,
    IReadMetadata registry_,
    Authority authority
  ) ERC1155(baseUri_) Auth(msg.sender, authority) {
    _registry = registry_;
    _uri = baseUri_;
  }

  modifier onlyValidator() {
    bool isActive = isValidator[IMintValidator(msg.sender)];
    require(isActive, "VALIDATOR_INACTIVE");
    _;
  }

  /**
   * @dev query URI for a token Id. Queries the Metadata registry on the backend
   */
  function uri(uint256 _id) public view override returns (string memory) {
    return string(abi.encodePacked(_uri, _registry.get(_id)));
  }

  /**
   * @dev change the URI base address after construction.
   */
  function setBaseURI(string calldata _newBaseUri) external requiresAuth {
    _setURI(_newBaseUri);
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
  function addValidator(IMintValidator _validator, uint256[] memory ids)
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
  function removeValidator(IMintValidator _validator, uint256[] memory ids)
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
   * @dev Mint mulitiple tokens at different quantities. This is an onlyOwner-guareded
          function and is meant basically as a sudo-command.
   */
  function mintBatch(
    address _to,
    uint256[] memory _ids,
    uint256[] memory _amounts,
    bytes memory _data
  ) external virtual requiresAuth {
    _mintBatch(_to, _ids, _amounts, _data);
    _updateMintedQuantities(_ids, _amounts);
  }

  /**
   * @dev Creates `amount` new tokens for `to`, of token type `id`.
   *      At least one Validator must be active in order to utilized this interface.
   */
  function modularMintInit(
    uint256 _dropId,
    address _to,
    uint256[] memory _requestedAmounts,
    bytes memory _data,
    IMintValidator _validator,
    string calldata _metadata
  ) public virtual override {
    require(isValidator[_validator], "BAD_VALIDATOR");
    _validator.validate(_to, _dropId, _requestedAmounts, _metadata, _data);
  }

  /**
   * @dev Creates `amount` new tokens for `to`, of token type `id`.
   *      At least one Validator must be active in order to utilized this interface.
   */
  function modularMintCallback(
    address recipient,
    uint256[] calldata _ids,
    uint256[] calldata _requestedAmounts,
    bytes calldata _data
  ) public virtual override onlyValidator {
    for (uint256 i; i < _ids.length; i++) {
      require(idToValidator[_ids[i]] == address(msg.sender), "INVALID_MINT");
    }
    _mintBatch(recipient, _ids, _requestedAmounts, _data);
    _updateMintedQuantities(_ids, _requestedAmounts);
  }
  /**
   * @dev Creates `amount` new tokens for `to`, of token type `id`.
   *      At least one Validator must be active in order to utilized this interface.
   */
  function modularMintCallbackSingle(
    address recipient,
    uint256 _id,
    bytes calldata _data
  ) public virtual onlyValidator {
      require(idToValidator[_id] == address(msg.sender), "INVALID_MINT");
    uint256[] memory ids = new uint256[](1);
    uint256[] memory amounts = new uint256[](1);
    ids[0] = _id;
    amounts[0] = 1;
    _mintBatch(recipient, ids, amounts, _data);
    _updateMintedQuantities(ids, amounts);
  }

  function _updateMintedQuantities(
    uint256[] memory _ids,
    uint256[] memory _amounts
  ) internal {
    require(_ids.length == _amounts.length, "MINT_QUANTITY_MISMATCH");
    for (uint256 i = 0; i < _ids.length; i++) {
      quantityMinted[_ids[i]] += _amounts[i];
    }
  }

  function _updateMintedQuantity(uint256 _id, uint256 _amount) internal {
    uint256[] memory ids = new uint256[](1);
    uint256[] memory amounts = new uint256[](1);
    ids[0] = _id;
    amounts[0] = _amount;
    _updateMintedQuantities(ids, amounts);
  }
}

