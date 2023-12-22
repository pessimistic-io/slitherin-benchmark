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
}
