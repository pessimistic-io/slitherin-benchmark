// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {IERC1155} from "./IERC1155.sol";
import {Ownable} from "./Ownable.sol";
import {MerkleProof} from "./MerkleProof.sol";

contract Drop1155 is Ownable {
    /// ============ Immutable storage ============
    /// @notice ERC20-claimee inclusion root
    IERC1155 public immutable dropToken;
    uint256 public immutable withdrawTime;
    uint256 public immutable assetID;
    uint256 public immutable pricePerToken;
    bool public isOpenForAll;
    /// ============ Mutable storage ============

    /// @notice Mapping of addresses who have claimed tokens
    mapping(address => bool) public hasClaimed;
    bytes32 public merkleRoot;
    /// ============ Errors ============

    /// @notice Thrown if address has already claimed
    error AlreadyClaimed();
    /// @notice Thrown if address/amount are not part of Merkle tree
    error NotInMerkle();
    error InsufficientAllowance();
    error InvalidValue();
    error NotWithdrawTime();
    error NotOpen();

    constructor(
        bytes32 _merkleRoot,
        uint256 _withdrawTime,
        uint256 _assetID,
        uint256 _pricePerToken, // price for 1 token not 1e18
        IERC1155 _dropToken
    ) {
        merkleRoot = _merkleRoot; // Update root
        withdrawTime = _withdrawTime;
        assetID = _assetID;
        pricePerToken = _pricePerToken;
        dropToken = _dropToken;
    }

    /// ============ Events ============

    event Claim(address indexed to, uint256 amount);

    /// ============ Functions ============
    function claim(address _to, uint256 _amount, uint256 _maxAllowance, bytes32[] calldata _proof) external payable {
        // Leaf => hash(tokenID, to, maxAllowance, pricePerToken)

        // Throw if address tries to claim more than they are allowed
        if (_amount > _maxAllowance) revert InsufficientAllowance();
        if (msg.value != _amount * pricePerToken) revert InvalidValue();

        // Throw if address has already claimed tokens
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();

        hasClaimed[msg.sender] = true;

        // Verify merkle proof, or revert if not in tree
        bytes32 _leaf = keccak256(abi.encodePacked(msg.sender, _maxAllowance));
        bool _isValidLeaf = MerkleProof.verify(_proof, merkleRoot, _leaf);

        // Throw if leaf isn't in tree
        if (!_isValidLeaf) revert NotInMerkle();

        // Transfer tokens to address
        dropToken.safeTransferFrom(address(this), _to, assetID, _amount, "0x");

        // Emit claim event
        emit Claim(_to, _amount);
    }

    function claimOpen(address _to, uint256 _amount) external payable {

        if (!isOpenForAll) revert NotOpen();
        if (msg.value != _amount * pricePerToken) revert InvalidValue();

        // Transfer tokens to address
        dropToken.safeTransferFrom(address(this), _to, assetID, _amount, "0x");

        // Emit claim event
        emit Claim(_to, _amount);
    }

    function withdraw(IERC1155 _token, uint256 _amount, address _to, uint256 tokenID) external onlyOwner {
        if (block.timestamp < withdrawTime) revert NotWithdrawTime();
        _token.safeTransferFrom(address(this), _to, tokenID, _amount, "0x");
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setOpenForAll() external onlyOwner {
        isOpenForAll = true;
    }

    function withdrawFunds(address _to) external onlyOwner {
        // Just transfer funds
        _to.call{value: address(this).balance}("");
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }
}

