//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155BurnableUpgradeable.sol";
import "./StringsUpgradeable.sol";

import "./ISmolRacingTrophies.sol";
import "./SmolRacingTrophiesState.sol";

contract SmolRacingTrophies is Initializable, ISmolRacingTrophies, SmolRacingTrophiesState {
    using StringsUpgradeable for uint256;

    function initialize() external initializer {
        SmolRacingTrophiesState.__SmolRacingTrophiesState_init();
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
        require(to == address(0) || from == address(0), "Soulbound tokens can only be minted and burned");
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function mint(address _to, uint256 _id, uint256 _amount) external override requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) whenNotPaused {

        _mint(_to, _id, _amount, "");
    }

    function adminSafeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount) external override requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) whenNotPaused {
        _safeTransferFrom(_from, _to, _id, _amount, "");
    }

    function adminSafeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _amounts) external override requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) whenNotPaused {
        _safeBatchTransferFrom(_from, _to, _ids, _amounts, "");
    }

    function burn(
        address account,
        uint256 id,
        uint256 value
    ) public override(ISmolRacingTrophies, ERC1155BurnableUpgradeable) {
        super.burn(account, id, value);
    }

    function burnBatch(
        address account,
        uint256[] memory ids,
        uint256[] memory values
    ) public override(ISmolRacingTrophies, ERC1155BurnableUpgradeable) {
        super.burnBatch(account, ids, values);
    }

    function setBaseUri(string memory _baseURI) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        baseURI = _baseURI;
        emit BaseUriChanged(_baseURI);
    }

    function uri(uint256 typeId)
        public
        view                
        override
        returns (string memory)
    {
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, typeId.toString(), '.json')) : baseURI;
    }

}
