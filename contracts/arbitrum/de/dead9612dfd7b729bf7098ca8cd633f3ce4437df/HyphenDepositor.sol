// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <=0.8.19;

import "./IERC20.sol";
import "./StorageSlot.sol";

interface IHyphen {
    function depositErc20(
        uint256 toChainId,
        address tokenAddress,
        address receiver,
        uint256 amount,
        string calldata tag
    ) external;

    function depositNative(
        address receiver,
        uint256 toChainId,
        string calldata tag
    ) external payable;
}

contract HyphenDepositor {
    bytes32 private constant HYPHEN_SLOT = 0x3faf5b18265d72e61a671bb2a8f13a812c68b994bf4f0f4073a32cf53fc2349a;  // keccak256("HyphenDepositor.hyphen")
    address internal immutable OWNER;

    constructor(address owner) {
        OWNER = owner;
    }

    function initialize(address _hyphen) public payable {
        require(msg.sender == OWNER || address(this) == OWNER);
        StorageSlot.getAddressSlot(HYPHEN_SLOT).value = _hyphen;
    }

    function depositAllErc20(address receiver, uint256 toChainId, address tokenAddress) public payable {
        IHyphen(StorageSlot.getAddressSlot(HYPHEN_SLOT).value).depositErc20(
            toChainId,
            tokenAddress,
            receiver,
            IERC20(tokenAddress).balanceOf(address(this)),
            ""
        );
    }

    function depositAllNative(address receiver, uint256 toChainId) public payable {
        IHyphen(StorageSlot.getAddressSlot(HYPHEN_SLOT).value).depositNative{
            value: address(this).balance
        }(
            receiver,
            toChainId,
            ""
        );
    }
}

