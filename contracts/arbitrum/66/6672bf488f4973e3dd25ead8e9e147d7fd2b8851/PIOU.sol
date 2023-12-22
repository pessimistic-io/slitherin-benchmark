// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "./MerkleProof.sol";

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {Ownable} from "./Ownable.sol";

contract PIOU is ERC20("PIOU", "PIOU Stream Bearing Token", 18), Ownable {
    using SafeTransferLib for ERC20;

    bytes32 public merkleRoot;
    ERC20 public immutable asset =
        ERC20(0x33502E2C821b6dD7ED49d368f5479D0Be52395Db);

    address public treasury = address(0);
    uint256 public stableSwapRate = 746;
    uint256 public totalClaimed;
    mapping(address => uint256) public claimedByAddress;

    constructor(
        bytes32 _merkleRoot,
        address _owner,
        address _treasury
    ) {
        merkleRoot = _merkleRoot;
        treasury = _treasury;
        transferOwnership(_owner);
    }

    function claim(
        address _to,
        uint256 _allocation,
        bytes32[] calldata merkleProof
    ) external {
        // Verify the merkle proof.
        require(
            _verify(msg.sender, _allocation, merkleProof),
            "Merkle Tree: Invalid proof."
        );
        require(
            claimedByAddress[msg.sender] < _allocation,
            "Merkle Tree: Already claimed."
        );

        uint256 amountLeft = _allocation - claimedByAddress[msg.sender];
        // Mark it claimed and send the token.
        totalClaimed += amountLeft;
        claimedByAddress[msg.sender] += amountLeft;
        _mint(_to, (amountLeft * 10**18) / 5);
    }

    function claimStable(
        address _to,
        uint256 _allocation,
        bytes32[] calldata merkleProof
    ) external {
        // Verify the merkle proof.
        require(
            _verify(msg.sender, _allocation, merkleProof),
            "Merkle Tree: Invalid proof."
        );
        require(
            claimedByAddress[msg.sender] < _allocation,
            "Merkle Tree: Already claimed."
        );

        uint256 amountLeft = _allocation - claimedByAddress[msg.sender];
        // Mark it claimed and send the token.
        totalClaimed += amountLeft;
        claimedByAddress[msg.sender] += amountLeft;
        require(
            asset.allowance(treasury, address(this)) >=
                (amountLeft * stableSwapRate),
            "Not enough allowance in treasury"
        );
        asset.safeTransferFrom(treasury, _to, (amountLeft * stableSwapRate));
    }

    function setStableSwapRate(uint256 _stableSwapRate) external onlyOwner {
        stableSwapRate = _stableSwapRate;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setTreasuryAddress(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function _leaf(address account, uint256 allocation)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(account, ",", allocation));
    }

    function _verify(
        address account,
        uint256 allocation,
        bytes32[] calldata merkleProof
    ) public view returns (bool) {
        bytes32 leafToCheck = _leaf(account, allocation);
        bool isValid = MerkleProof.verify(merkleProof, merkleRoot, leafToCheck);
        return isValid;
    }
}

