// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MerkleProof.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ITokenManager.sol";


contract Airdrop is Ownable {
    using SafeERC20 for IERC20;

    address public token;
    bytes32 public root;
    address public tokenManager;

    mapping(address => bool) public claimed;

    constructor(address _token, bytes32 _root, address _tokenManager) {
      token = _token;
      root = _root;
      tokenManager = _tokenManager;

      IERC20(token).approve(address(tokenManager), type(uint256).max);
    }

    function updateRoot(bytes32 _root) external onlyOwner {
      root = _root;
    }

    function updatetoken(address _token) external onlyOwner {
      token = _token;
    }

    function recoverTokens(uint256 _amount) external onlyOwner {
      IERC20(token).safeTransfer(msg.sender, _amount);
    }

    function _verify(bytes32[] memory _proof, address _address, uint256 _amount) private view returns (bool) {
      bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(_address, _amount))));

      return MerkleProof.verify(_proof, root, leaf);
    }

    function claim(bytes32[] memory _proof, uint256 _amount) external {
      require(!claimed[msg.sender], "Already claimed");
      require(_verify(_proof, msg.sender, _amount), "Merkle verification failed");
      require(_amount <= IERC20(token).balanceOf(address(this)), "Not enough tokens");

      claimed[msg.sender] = true;

      // Convert all STEADY tokens to esSTEADY
      ITokenManager(tokenManager).convertTo(_amount, msg.sender);
    }
}

