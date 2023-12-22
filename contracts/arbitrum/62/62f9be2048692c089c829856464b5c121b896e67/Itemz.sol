//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ItemzContracts.sol";

contract Itemz is Initializable, ItemzContracts {

    function initialize() external initializer {
        ItemzContracts.__ItemzContracts_init();
    }

    function burn(
        address _from,
        uint256 _id,
        uint256 _amount)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    {
        _burn(_from, _id, _amount);
    }

    function mint(
        address _to,
        uint256 _id,
        uint256 _amount)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    tokenIdExists(_id)
    {
        _mint(_to, _id, _amount, "");
    }

    function mintBatch(
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _amounts)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    {
        for(uint256 i = 0; i < _ids.length; i++) {
            require(exists(_ids[i]), "Itemz: ID does not exist");
        }
        _mintBatch(_to, _ids, _amounts, "");
    }

    function airdropSingle(
        address[] calldata _tos,
        uint256 _id,
        uint256 _amount)
    external
    whenNotPaused
    onlyAdminOrOwner
    {
        require(_tos.length > 0, "Items: Bad length");
        require(exists(_id), "Itemz: ID does not exist");
        require(_amount > 0, "Itemz: Bad airdrop amount");

        for(uint256 i = 0; i < _tos.length; i++) {
            _mint(_tos[i], _id, _amount, "");
        }
    }

    function airdropMulti(
        address[] calldata _tos,
        uint256[] calldata _ids,
        uint256[] calldata _amounts)
    external
    whenNotPaused
    onlyAdminOrOwner
    {
        require(_tos.length > 0 && _tos.length == _ids.length && _ids.length == _amounts.length, "Items: Bad length");

        for(uint256 i = 0; i < _tos.length; i++) {
            require(exists(_ids[i]), "Itemz: ID does not exist");
            require(_amounts[i] > 0, "Itemz: Bad airdrop amount");
            _mint(_tos[i], _ids[i], _amounts[i], "");
        }
    }
}
