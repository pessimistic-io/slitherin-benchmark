// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Drop1155} from "./Drop1155.sol";
import {Drop20} from "./Drop20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {IERC1155} from "./IERC1155.sol";

contract DropFactory {
    event DeployDrop1155(IERC1155 dropToken, uint256 assetID, Drop1155 drop);
    event DeployDrop20(IERC20 dropToken, uint256 amt, Drop20 drop);

    Drop1155[] public erc1155Drops;
    Drop20[] public erc20Drops;

    function deployDrop1155(
        bytes32 _merkleRoot,
        uint256 _maxMints,
        uint256 _withdrawTime,
        uint256 _assetID,
        uint256 _pricePerToken,
        IERC1155 _dropToken,
        address _owner
    ) external {
        Drop1155 _drop = new Drop1155(_merkleRoot, _withdrawTime, _assetID, _pricePerToken, _dropToken);
        _dropToken.safeTransferFrom(msg.sender, address(_drop), _assetID, _maxMints, "0x");
        _drop.transferOwnership(_owner);
        erc1155Drops.push(_drop);
        emit DeployDrop1155(_dropToken, _assetID, _drop);
    }

    function deployDrop20(
        bytes32 _merkleRoot,
        IERC20 _dropToken,
        uint256 _withdrawTime,
        uint256 _pricePerToken, // price for 10^decimal tokens
        uint256 _amount,
        address _owner
    ) external {
        Drop20 _drop = new Drop20(_merkleRoot, _dropToken, _withdrawTime, _pricePerToken);
        SafeERC20.safeTransferFrom(_dropToken, msg.sender, address(_drop), _amount);
        _drop.transferOwnership(_owner);
        erc20Drops.push(_drop);
        emit DeployDrop20(_dropToken, _amount, _drop);
    }
}

