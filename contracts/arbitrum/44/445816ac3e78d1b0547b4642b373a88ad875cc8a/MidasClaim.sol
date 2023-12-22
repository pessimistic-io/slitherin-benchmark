// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Ownable.sol";
import "./MerkleProof.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

import "./ILSDepositaryFacet.sol";

contract MidasClaim is Ownable {
    using SafeERC20 for IERC20;

    error AlreadyClaimed(address);
    error ProofIsNotValid(address, bytes32);
    error CannotBeZeroBytes32();
    error CannotBeZeroAddress();

    event MerkleRootChanged(bytes32 indexed oldRoot, bytes32 indexed newRoot);
    event NewClaimingTokenSet(address indexed oldToken, address indexed newToken);
    event NewTreasurySet(address indexed oldToken, address indexed newToken);
    event EmergencyExitCalled();

    IERC20 public token;
    address public treasury;
    bytes32 public merkleRoot;
    ILSDepositaryFacet public stLocus;

    mapping(address user => uint256 claimed) public claimed;

    constructor(
        address _token,
        address _stLocus,
        bytes32 _merkleRoot,
        address _treasury
    ) {
        token = IERC20(_token);
        merkleRoot = _merkleRoot;
        stLocus = ILSDepositaryFacet(_stLocus);
        treasury = _treasury;
        token.approve(address(stLocus), type(uint256).max);
    }

    function setNewMerkleRoot(bytes32 _newRoot) external onlyOwner {
        if (_newRoot == bytes32(0)) {
            revert CannotBeZeroBytes32();
        }
        emit MerkleRootChanged(merkleRoot, _newRoot);
        merkleRoot = _newRoot;
    }

    function setNewToken(address _newToken) external onlyOwner {
        if (_newToken == address(0)) {
            revert CannotBeZeroAddress();
        }
        emit NewClaimingTokenSet(address(token), _newToken);
        token = IERC20(_newToken);
    }

    function setNewTreasury(address _newTreasury) external onlyOwner {
        if (_newTreasury == address(0)) {
            revert CannotBeZeroAddress();
        }
        emit NewTreasurySet(treasury, _newTreasury);
        treasury = _newTreasury;
    }

    function claim(
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external {
        if (claimed[account] >= amount) revert AlreadyClaimed(account);
        bytes32 leaf = keccak256(abi.encodePacked(keccak256(abi.encode(account, amount))));
        bool isValidProof = MerkleProof.verify(merkleProof, merkleRoot, leaf);
        if (!isValidProof) revert ProofIsNotValid(account, leaf);
        claimed[account] += amount;
        stLocus.stakeFor(account, amount);
    }

    function emergencyExit() external onlyOwner {
        token.safeTransfer(treasury, token.balanceOf(address(this)));
        emit EmergencyExitCalled();
    }
}

