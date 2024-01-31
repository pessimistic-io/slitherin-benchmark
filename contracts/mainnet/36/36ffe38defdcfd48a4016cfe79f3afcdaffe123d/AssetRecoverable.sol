// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC721Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./IERC1155Upgradeable.sol";

/// @title Asset Recoverable
/// @author Chain Labs
/// @notice module to recover any stuck assets in the contract
contract AssetRecoverable {
    /// @notice recover ERC721 tokens
    /// @param _erc721 address of erc721 token contract
    /// @param _receiver receiver address
    /// @param _id ID of ERC721 token to be recovered
    function _recoverERC721(
        address _erc721,
        address _receiver,
        uint256 _id
    ) internal virtual {
        IERC721Upgradeable(_erc721).transferFrom(address(this), _receiver, _id);
    }

    /// @notice recover stuck ERC20
    /// @param _erc20 address of erc20 token contract
    /// @param _receiver receiver address
    /// @param _amount amount of token to be recovered
    function _recoverERC20(
        address _erc20,
        address _receiver,
        uint256 _amount
    ) internal virtual {
        IERC20Upgradeable(_erc20).transfer(_receiver, _amount);
    }

    /// @notice recover stuck ERC1155 tokens
    /// @param _erc1155 address of erc1155 token contract
    /// @param _receiver receiver address
    /// @param _id ID of ERC1155 token to be recovered
    /// @param _amount amount of ERC1155's ID token to be recovered
    function _recoverERC1155(
        address _erc1155,
        address _receiver,
        uint256 _id,
        uint256 _amount
    ) internal virtual {
        IERC1155Upgradeable(_erc1155).safeTransferFrom(
            address(this),
            _receiver,
            _id,
            _amount,
            ""
        );
    }
}

