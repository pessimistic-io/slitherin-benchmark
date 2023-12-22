pragma solidity 0.8.4;

// SPDX-License-Identifier: BUSL-1.1

import "./Interfaces.sol";

import "./IERC721.sol";
import "./Ownable.sol";

contract TraderNFT is ITraderNFT, Ownable {
    uint256[] public updatedBatchIds;
    IERC721 public nftAddress;
    mapping(uint256 => uint8) public override tokenTierMappings;

    constructor(IERC721 _nftAddress) {
        nftAddress = _nftAddress;
    }

    function updateTokenTier(
        uint256[] calldata _tokenIds,
        uint8[] calldata _tiers,
        uint256[] calldata _batchIds
    ) external onlyOwner {
        for (uint256 index = 0; index < _tokenIds.length; index++) {
            tokenTierMappings[_tokenIds[index]] = _tiers[index];
        }

        for (uint256 index = 0; index < _batchIds.length; index++) {
            updatedBatchIds.push(_batchIds[index]);
        }
        emit UpdateTiers(_tokenIds, _tiers, _batchIds);
    }

    function tokenOwner(uint256 id)
        external
        view
        override
        returns (address user)
    {
        try nftAddress.ownerOf(id) returns (address _user) {
            user = _user;
        } catch Error(string memory reason) {
            user = address(0);
        }
    }

    function getUpdatedBatchIds() external view returns (uint256[] memory) {
        return updatedBatchIds;
    }
}

