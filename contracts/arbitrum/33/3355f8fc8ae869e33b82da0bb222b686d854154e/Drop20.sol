// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {MerkleProof} from "./MerkleProof.sol";
import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";

contract Drop20 is Ownable {
    IERC20 public immutable dropToken;
    uint256 public immutable withdrawTime;
    uint256 public immutable pricePerToken;
    /// ============ Mutable storage ============

    /// @notice Mapping of addresses who have claimed tokens
    mapping(address => bool) public hasClaimed;
    bytes32 public merkleRoot;
    bool public isOpenForAll;

    /// ============ Errors ============
    /// @notice Thrown if address has already claimed
    error AlreadyClaimed();
    /// @notice Thrown if address/amount are not part of Merkle tree
    error NotInMerkle();
    error InsufficientAllowance();
    error InvalidValue();
    error NotWithdrawTime();
    error NotOpen();

    /// @notice Creates a new MerkleClaimERC20 contract
    /// @param _merkleRoot of claimees
    constructor(bytes32 _merkleRoot, IERC20 _dropToken, uint256 _withdrawTime, uint256 _pricePerToken) {
        merkleRoot = _merkleRoot; // Update root
        dropToken = IERC20(_dropToken);
        withdrawTime = _withdrawTime;
        pricePerToken = _pricePerToken;
    }

    /// ============ Events ============

    /// @notice Emitted after a successful token claim
    /// @param to recipient of claim
    /// @param amount of tokens claimed
    event Claim(address indexed to, uint256 amount);

    /// ============ Functions ============

    function claim(address _to, uint256 _amount, uint256 _maxAllowance, bytes32[] calldata _proof) external payable {
        // Throw if address has already claimed tokens
        if (hasClaimed[_to]) revert AlreadyClaimed();
        // Throw if address tries to claim more than they are allowed
        if (_amount > _maxAllowance) revert InsufficientAllowance();
        if (msg.value * 1e18 != (_amount * pricePerToken)) revert InvalidValue();
        // Verify merkle proof, or revert if not in tree
        bytes32 _leaf = keccak256(abi.encodePacked(msg.sender, _maxAllowance));
        bool isValidLeaf = MerkleProof.verify(_proof, merkleRoot, _leaf);
        if (!isValidLeaf) revert NotInMerkle();

        // Set address to claimed
        hasClaimed[_to] = true;

        // Transfer tokens to address
        dropToken.transfer(_to, _amount);

        // Emit claim event
        emit Claim(_to, _amount);
    }

    function claimOpen(address _to, uint256 _amount) external payable {
        if (!isOpenForAll) revert NotOpen();
        if (msg.value * 1e18 != (_amount * pricePerToken)) revert InvalidValue();

        // Transfer tokens to address
        dropToken.transfer(_to, _amount);

        // Emit claim event
        emit Claim(_to, _amount);
    }

    function withdraw(uint256 _amount, address _to) external onlyOwner {
        if (block.timestamp < withdrawTime) revert NotWithdrawTime();
        dropToken.transfer(_to, _amount);
    }

    function setOpenForAll() external onlyOwner {
        isOpenForAll = true;
    }

    function withdrawFunds(address _to) external onlyOwner {
        // Just transfer funds
        _to.call{value: address(this).balance}("");
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }
}

