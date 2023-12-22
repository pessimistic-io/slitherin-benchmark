//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TreasureBadgesAdmin.sol";

contract TreasureBadges is Initializable, TreasureBadgesAdmin {
    using StringsUpgradeable for uint256;

    function initialize() external initializer {
        TreasureBadgesAdmin.__TreasureBadgesAdmin_init();
    }

    function isApprovedForAll(
        address _account,
        address _operator
    ) public view override(ERC1155Upgradeable, IERC1155Upgradeable) returns (bool) {
        return hasRole(ADMIN_ROLE, _operator) || hasRole(OWNER_ROLE, _operator)
            || super.isApprovedForAll(_account, _operator);
    }

    function totalSupply() public view returns (uint256) {
        return totalMinted - totalBurned;
    }

    function tokenSupply(uint256 _tokenId) public view returns (uint256) {
        return tokensMinted[_tokenId] - tokensBurned[_tokenId];
    }

    function uri(uint256 _typeId) public view virtual override returns (string memory) {
        return bytes(_uri).length > 0
            ? string(abi.encodePacked(_uri, uint256(uint160(address(this))).toHexString(20), "/", _typeId.toString()))
            : _uri;
    }

    function _beforeTokenTransfer(
        address _operator,
        address _from,
        address _to,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        bytes memory _data
    ) internal override {
        super._beforeTokenTransfer(_operator, _from, _to, _ids, _amounts, _data);

        require(
            hasRole(ADMIN_ROLE, msg.sender) || hasRole(OWNER_ROLE, msg.sender),
            "TreasureBadges: Only admin or owner can transfer TreasureBadges"
        );
        require(_from != address(0) || _to != address(0), "TreasureBadges: from or to need to be non-zero addresses.");
        for (uint256 i = 0; i < _ids.length; i += 1) {
            uint256 _id = _ids[i];
            uint256 _amount = _amounts[i];

            if (_from == address(0)) {
                totalMinted += _amount;
                tokensMinted[_id] += _amount;
            } else if (_to == address(0)) {
                totalBurned += _amount;
                tokensBurned[_id] += _amount;
            }
        }
    }
}

