// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./MerkleProof.sol";
import "./Ownable.sol";

contract Claim is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public immutable token;
    bytes32 public merkleRoot;
    mapping(address => uint256) public claimedAmount;
    bool public claimOpen = false;
    uint256 public claimed = 0;

    constructor(IERC20 _contract){
	token = _contract;
    }

    function claim(uint256 _count, bytes32[] memory _proof) public {
	require(claimOpen, "Claim closed");
	require(_count > 0, "Zero tokens to claim");
	require(_count < token.balanceOf(address(this)), "Not enought tokens to claim");
	require(claimedAmount[msg.sender] == 0, "Already claimed");

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender,_count))));
        require(MerkleProof.verify(_proof, merkleRoot, leaf), "Invalid proof");

	token.safeTransfer(msg.sender,_count);

	claimedAmount[msg.sender] = _count;
	claimed = claimed + _count;
    }

    function setRoot(bytes32 _root) external onlyOwner {
	merkleRoot = _root;
    }

    function setClaimState(bool _state) external onlyOwner {
	claimOpen = _state;
    }

    function rescueToken() external onlyOwner {
        token.safeTransfer(msg.sender,IERC20(token).balanceOf(address(this)));
    }
    function rescueETH() external onlyOwner {
	uint256 balance = address(this).balance;
	Address.sendValue(payable(owner()), balance);
    }

}


