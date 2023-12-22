// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {IERC721} from "./IERC721.sol";
import {IERC1155} from "./IERC1155.sol";

error TransferFailed();
error LengthsNotEqual();

contract Airdrop is Ownable {
    IERC20 public token;
    IERC721 public nft;
    IERC1155 public sNft;

    modifier checkLength(
        address[] calldata _receiver,
        uint256[] calldata _tokenId
    ) {
        if (_receiver.length != _tokenId.length) revert LengthsNotEqual();
        _;
    }

    function setContractERC20(address _token) external onlyOwner {
        token = IERC20(_token);
    }

    function setContractERC721(address _token) external onlyOwner {
        nft = IERC721(_token);
    }

    function setContractERC1155(address _token) external onlyOwner {
        sNft = IERC1155(_token);
    }

    function airdropERC20(
        address sender,
        address[] calldata _receiver,
        uint256 _amount
    ) external onlyOwner {
        uint256 i;
        for (; i < _receiver.length; ++i)
            token.transferFrom(sender, _receiver[i], _amount);
    }

    function airdropERC721(
        address sender,
        address[] calldata _receiver,
        uint256[] calldata _tokenId
    ) external checkLength(_receiver, _tokenId) onlyOwner {
        uint256 i;
        for (; i < _receiver.length; ++i)
            nft.transferFrom(sender, _receiver[i], _tokenId[i]);
    }

    function airdropERC1155(
        address sender,
        address[] calldata _receiver,
        uint256[] calldata _tokenId,
        uint256 amount
    ) external checkLength(_receiver, _tokenId) onlyOwner {
        if (_receiver.length != _tokenId.length) revert LengthsNotEqual();

        uint256 i;
        for (; i < _receiver.length; ++i)
            sNft.safeTransferFrom(
                sender,
                _receiver[i],
                _tokenId[i],
                amount,
                ""
            );
    }

    function removeEth() external onlyOwner {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        if (!success) revert TransferFailed();
    }
}

