//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155BurnableUpgradeable.sol";

import "./ISmolTreasures.sol";
import "./SmolTreasuresState.sol";

contract SmolTreasures is Initializable, ISmolTreasures, SmolTreasuresState {

    function initialize() external initializer {
        SmolTreasuresState.__SmolTreasuresState_init();
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        require(!paused(), "No token transfer while paused");
    }

    function mint(address _to, uint256 _id, uint256 _amount) external override onlyAdminOrOwner whenNotPaused {

        _mint(_to, _id, _amount, "");
    }

    function adminSafeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount) external override onlyAdminOrOwner whenNotPaused {
        _safeTransferFrom(_from, _to, _id, _amount, "");
    }

    function adminSafeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _amounts) external override onlyAdminOrOwner whenNotPaused {
        _safeBatchTransferFrom(_from, _to, _ids, _amounts, "");
    }

    function burn(
        address account,
        uint256 id,
        uint256 value
    ) public override(ISmolTreasures, ERC1155BurnableUpgradeable) {
        super.burn(account, id, value);
    }

    function burnBatch(
        address account,
        uint256[] memory ids,
        uint256[] memory values
    ) public override(ISmolTreasures, ERC1155BurnableUpgradeable) {
        super.burnBatch(account, ids, values);
    }

}
