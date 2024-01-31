// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC1155.sol";
import "./AccessControl.sol";
import "./Counters.sol";
import "./Strings.sol";
import "./Utils.sol";

contract YeyeTrait is ERC1155, AccessControl {
    /* =============================================================
    * CONSTANTS
    ============================================================= */

    bytes32 public constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");
    bytes32 public constant TRAITS_SETTER_ROLE = keccak256("TRAITS_SETTER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    /* =============================================================
    * STRUCTS
    ============================================================= */

    struct Trait {
        bool exist;
        bytes32 list;
    }

    struct SetTrait {
        uint grade;
        bytes32 list;
    }

    struct TraitKey {
        uint256 id;
        uint grade;
        bytes32[] key;
    }

    /* =============================================================
    * STATES
    ============================================================= */

    // Name of the collection
    string public name = "YEYEVERSE: Traits";

    // Trait List
    mapping (uint => Trait) private traits;

    /* =============================================================
    * CONSTRUCTOR
    ============================================================= */

    constructor(string memory _uri) ERC1155(_uri) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(URI_SETTER_ROLE, msg.sender);
        _grantRole(TRAITS_SETTER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(FACTORY_ROLE, msg.sender);
    }

    /* =============================================================
    * SETTERS
    ============================================================= */

    /*
    * @dev set Uri of Metadata, make sure include trailing slash (https://somedomain.com/metadata/)
    */
    function setUri(string memory _newUri) public onlyRole(URI_SETTER_ROLE) {
        ERC1155._setURI(_newUri);
    }

    /*
    * @dev set trait list
    */
    function setTraits(SetTrait[] calldata _newTraits) public onlyRole(TRAITS_SETTER_ROLE) {
        for (uint i = 0; i < _newTraits.length; i++) {
            traits[_newTraits[i].grade] = Trait(true, _newTraits[i].list);
        }
    }

    /*
    * @dev set trait list
    */
    function unsetGrade(uint[] calldata _grade) public onlyRole(TRAITS_SETTER_ROLE) {
        for (uint i = 0; i < _grade.length; i++) {
            traits[_grade[i]] = Trait(false, bytes32(0));
        }
    }

    /* =============================================================
    * GETTERS
    ============================================================= */

    /*
    * @dev get Uri of corresponding ID, this will produce link to uri{ID}
    */
    function uri(uint256 _tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(ERC1155.uri(_tokenId), Strings.toString(_tokenId)));
    }

    /*
    * @dev verify trait
    */
    function traitCheck(uint256 _id, uint _grade, bytes32[] calldata _keys) public view returns (bool result) {
        Trait memory grade = traits[_grade];
        require(grade.exist, "Legendary trait unavailable");
        result = Utils.tokenCheck(grade.list, _id, _keys);
    }

    /* =============================================================
    * MAIN FUNCTION
    ============================================================= */

    /*
    * @dev mint already added NFT
    */
    function mint(address account, uint256 id, uint256 amount, bytes memory data) public onlyRole(MINTER_ROLE) {
        _mint(account, id, amount, data);
    }

    /*
    * @dev batch version of mint
    */
    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) public onlyRole(MINTER_ROLE) {
        _mintBatch(to, ids, amounts, data);
    }

    /*
    * @dev function for factory to burn stored token
    */
    function factoryBurn(address account, uint256 id, uint256 value) public onlyRole(FACTORY_ROLE) {
        _burn(account, id, value);
    }

    /*
    * @dev batch version of factoryBurn
    */
    function factoryBurnBatch(address account, uint256[] memory ids, uint256[] memory values) public onlyRole(FACTORY_ROLE) {
        _burnBatch(account, ids, values);
    }

    /* =============================================================
    * HOOKS
    ============================================================= */

    /*
    * @dev before token transfer hook
    */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    /*
    * @dev override required by ERC1155
    */
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

