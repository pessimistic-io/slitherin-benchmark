// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC721_IERC721Receiver.sol";

import "./INonfungiblePositionManager.sol";
import "./IPositionsVault.sol";
import "./IPositionsVaultManagement.sol";

contract PositionsVault is IPositionsVault, IPositionsVaultManagement, IERC721Receiver, Ownable {

    // Maps all position token ids to their owner at time of vaulting
    mapping(uint256 => address) public owners;

    address public operator;
    INonfungiblePositionManager public positionManager;

    constructor(INonfungiblePositionManager _positionManager) {
        positionManager = _positionManager;
    }

    function onERC721Received(address /*operator*/, address /*from*/, uint256 /*tokenId*/, bytes calldata /*data*/) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function put(uint256 _tokenId) external override returns (address owner) {
        require(msg.sender == operator, "Not allowed");
        owner = positionManager.ownerOf(_tokenId);
        owners[_tokenId] = owner;
        positionManager.safeTransferFrom(owner, address(this), _tokenId);

        emit Release(_tokenId, owner);
    }

    function collect(uint256 _tokenId) external override returns (uint256 token0Fees, uint256 token1Fees) {
        require(msg.sender == operator, "Not allowed");
        (token0Fees, token1Fees) = 
            positionManager.collect(INonfungiblePositionManager.CollectParams(_tokenId, 
                msg.sender, type(uint128).max, type(uint128).max));

        emit Collect(_tokenId, token0Fees, token1Fees);
    }

    function release(uint256 _tokenId) external override returns (address owner) {
        require(msg.sender == operator, "Not allowed");
        owner = owners[_tokenId];
        delete owners[_tokenId];
        positionManager.safeTransferFrom(address(this), owner, _tokenId);

        emit Release(_tokenId, owner);
    }

    function setOperator(address _operator) external override onlyOwner {
        operator = _operator;
    }
}

