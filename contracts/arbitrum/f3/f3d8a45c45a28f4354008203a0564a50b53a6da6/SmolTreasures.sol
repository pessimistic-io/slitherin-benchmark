//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155BurnableUpgradeable.sol";
import "./StringsUpgradeable.sol";

import "./ISmolTreasures.sol";
import "./SmolTreasuresState.sol";

contract SmolTreasures is Initializable, ISmolTreasures, SmolTreasuresState {
    using StringsUpgradeable for uint256;

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

    function setBaseUri(string memory _baseURI) external onlyAdminOrOwner {
        baseURI = _baseURI;
        emit BaseUriChanged(_baseURI);
    }

    function getNameOfTreasure(uint256 typeId) private pure returns (string memory) {
        if(typeId == 1) {
            return "Moon Rock";
        }
        if(typeId == 2) {
            return "Stardust";
        }
        if(typeId == 3) {
            return "Comet Shard";
        }
        if(typeId == 1) {
            return "Lunar Gold";
        }
        if(typeId == 1) {
            return "Alien Relic";
        }
        return "";
    }

    function uri(uint256 typeId)
        public
        view                
        override
        returns (string memory)
    {
        if(bytes(baseURI).length == 0 || typeId == 0) {
            return baseURI;
        }
        string memory metadata = string(abi.encodePacked(
            '{"name": "',
            getNameOfTreasure(typeId),
            '", "description": "An item harvested from the moon.", "image": "',
            string(abi.encodePacked(baseURI, (typeId - 1).toString(), '.gif')),
            '", "attributes": []',
            "}"
        ));

        return metadata;
    }

}
