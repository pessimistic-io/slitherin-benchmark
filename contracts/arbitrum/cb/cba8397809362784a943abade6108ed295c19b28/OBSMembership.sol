// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC1155.sol";
import "./Ownable.sol";

contract OBSMembership is ERC1155, Ownable {
    uint256 public constant MEMBER = 0;
    uint256 public constant CONTRIBUTOR = 1;

    constructor(string memory uri) ERC1155(uri) {}

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        revert("Membership is non-transferable");
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override {
        revert("Membership is non-transferable");
    }

    function mint(address to, uint256 id) external onlyOwner {
        require(balanceOf(to, id) == 0, "Membership already minted");
        _mint(to, id, 1, "");
    }

    function batchMint(
        address[] calldata to,
        uint256[] calldata ids
    ) external onlyOwner {
        unchecked {
            uint256 length = to.length;
            for (uint256 i = 0; i < length; ) {
                require(
                    balanceOf(to[i], ids[i]) == 0,
                    "Membership already minted"
                );
                _mint(to[i], ids[i], 1, "");
                i++;
            }
        }
    }

    function burn(address from, uint256 id, uint256 amount) external onlyOwner {
        _burn(from, id, amount);
    }

    function burnBatch(
        address from,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external onlyOwner {
        _burnBatch(from, ids, amounts);
    }

    function changeUri(string calldata newuri) external onlyOwner {
        _setURI(newuri);
    }

    function burnAll() external onlyOwner {
        address payable payableOwner = payable(owner());
        selfdestruct(payableOwner);
    }
}

