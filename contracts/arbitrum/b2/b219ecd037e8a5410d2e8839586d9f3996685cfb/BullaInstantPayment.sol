//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import "./SafeERC20.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./BoringBatchable.sol";

error ValueMustNoBeZero();
error NotContractOwner(address _sender);

contract BullaInstantPayment is BoringBatchable, Pausable, Ownable {
    using SafeERC20 for IERC20;

    event InstantPaymentTagUpdated(bytes32 indexed txAndLogIndexHash, address indexed updatedBy, string tag, uint256 blocktime);

    event InstantPayment(
        address indexed from,
        address indexed to,
        uint256 amount,
        address indexed tokenAddress,
        string description,
        string tag,
        string ipfsHash,
        uint256 blocktime
    );

    function pause() public whenNotPaused onlyOwner {
        _pause();
    }

    function unpause() public whenPaused onlyOwner {
        _unpause();
    }

    function instantPayment(
        address to,
        uint256 amount,
        address tokenAddress,
        string memory description,
        string memory tag,
        string memory ipfsHash
    ) public payable whenNotPaused {
        if (amount == 0) {
            revert ValueMustNoBeZero();
        }

        if (tokenAddress == address(0)) {
            (bool success, ) = to.call{ value: amount }('');
            require(success, 'Failed to transfer native tokens');
        } else {
            IERC20(tokenAddress).safeTransferFrom(msg.sender, to, amount);
        }

        emit InstantPayment(msg.sender, to, amount, tokenAddress, description, tag, ipfsHash, block.timestamp);
    }

    function updateBullaTag(bytes32 txAndLogIndexHash, string memory newTag) public {
        emit InstantPaymentTagUpdated(txAndLogIndexHash, msg.sender, newTag, block.timestamp);
    }
}

