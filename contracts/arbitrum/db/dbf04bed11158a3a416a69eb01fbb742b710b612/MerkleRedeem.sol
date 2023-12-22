// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.8.6;
pragma experimental ABIEncoderV2;

import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./MerkleProofUpgradeable.sol";

contract MerkleRedeem is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Claim {
        uint256 epoch;
        uint256 amount;
        bytes32[] merkleProof;
    }

    IERC20Upgradeable public token;

    event ClaimReward(address recipient, uint256 amount);
    event SeedAllocations(uint256 indexed epoch, bytes32 merkleRoot, uint256 totalAllocation);

    // Recorded epochs
    mapping(uint256 => bytes32) public epochMerkleRoots;
    mapping(uint256 => mapping(address => bool)) public claimed;

    function initialize(address token_) external initializer {
        __Ownable_init();
        token = IERC20Upgradeable(token_);
    }

    function seedAllocations(
        uint256 epoch,
        bytes32 merkleRoot,
        uint256 totalAllocation
    ) external onlyOwner {
        require(epochMerkleRoots[epoch] == bytes32(0), "Cannot rewrite merkle root");
        epochMerkleRoots[epoch] = merkleRoot;
        token.transferFrom(msg.sender, address(this), totalAllocation);
        emit SeedAllocations(epoch, merkleRoot, totalAllocation);
    }

    function claimEpoch(
        uint256 epoch,
        uint256 amount,
        bytes32[] memory merkleProof
    ) public {
        address recipient = msg.sender;
        require(!claimed[epoch][recipient], "Already claimed");
        require(verifyClaim(recipient, epoch, amount, merkleProof), "Incorrect merkle proof");

        claimed[epoch][recipient] = true;
        _disburse(recipient, amount);
    }

    function claimEpochs(Claim[] memory claims) public {
        address recipient = msg.sender;
        uint256 totalAmount = 0;
        Claim memory claim;
        for (uint256 i = 0; i < claims.length; i++) {
            claim = claims[i];
            if (claimed[claim.epoch][recipient]) {
                continue;
            }
            // require(!claimed[claim.epoch][recipient], "Already claimed");
            require(
                verifyClaim(recipient, claim.epoch, claim.amount, claim.merkleProof),
                "Incorrect merkle proof"
            );
            totalAmount += claim.amount;
            claimed[claim.epoch][recipient] = true;
        }
        _disburse(recipient, totalAmount);
    }

    function claimStatus(
        address account,
        uint256 begin,
        uint256 end
    ) external view returns (bool[] memory) {
        require(begin <= end, "Epochs must be specified in ascending order");
        uint256 size = 1 + end - begin;
        bool[] memory arr = new bool[](size);
        for (uint256 i = 0; i < size; i++) {
            arr[i] = claimed[begin + i][account];
        }
        return arr;
    }

    function merkleRoots(uint256 begin, uint256 end) external view returns (bytes32[] memory) {
        require(begin <= end, "Epochs must be specified in ascending order");
        uint256 size = 1 + end - begin;
        bytes32[] memory arr = new bytes32[](size);
        for (uint256 i = 0; i < size; i++) {
            arr[i] = epochMerkleRoots[begin + i];
        }
        return arr;
    }

    function verifyClaim(
        address recipient,
        uint256 epoch,
        uint256 amount,
        bytes32[] memory merkleProof
    ) public view returns (bool valid) {
        bytes32 leaf = keccak256(abi.encodePacked(recipient, amount));
        return MerkleProofUpgradeable.verify(merkleProof, epochMerkleRoots[epoch], leaf);
    }

    function _disburse(address recipient, uint256 amount) private {
        if (amount > 0) {
            emit ClaimReward(recipient, amount);
            token.safeTransfer(recipient, amount);
        }
    }
}

