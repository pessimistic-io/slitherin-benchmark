//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./BalancerCrystalContracts.sol";

contract BalancerCrystal is Initializable, BalancerCrystalContracts {

    function initialize() external initializer {
        BalancerCrystalContracts.__BalancerCrystalContracts_init();
    }

    function mint(
        address _to,
        uint256 _id,
        uint256 _amount)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    {
        _mint(_to, _id, _amount, "");
    }

    function adminSafeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    {
        _safeTransferFrom(_from, _to, _id, _amount, "");
    }

    function adminSafeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _amounts)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    {
        _safeBatchTransferFrom(_from, _to, _ids, _amounts, "");
    }
}
