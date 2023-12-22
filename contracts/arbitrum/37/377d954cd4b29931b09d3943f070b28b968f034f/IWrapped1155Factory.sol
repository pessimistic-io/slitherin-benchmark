// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC1155Receiver} from "./IERC1155Receiver.sol";

// @author Gnosis (https://github.com/gnosis/1155-to-20)
interface IWrapped1155Factory is IERC1155Receiver {
    function erc20Implementation() external view returns (address);

    function unwrap(address multiToken, uint256 tokenId, uint256 amount, address recipient, bytes calldata data)
        external;

    function batchUnwrap(
        address multiToken,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        address recipient,
        bytes calldata data
    ) external;

    function getWrapped1155DeployBytecode(address multiToken, uint256 tokenId, bytes calldata data)
        external
        view
        returns (bytes memory);

    function getWrapped1155(address multiToken, uint256 tokenId, bytes calldata data) external view returns (address);

    function requireWrapped1155(address multiToken, uint256 tokenId, bytes calldata data) external returns (address);
}

