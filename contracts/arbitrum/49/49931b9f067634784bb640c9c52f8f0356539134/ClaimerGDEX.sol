// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./MerkleProof.sol";
import "./SafeERC20.sol";
import "./Initializable.sol";


contract ClaimerGDEX is Ownable, Initializable {
  using SafeERC20 for IERC20;

  IERC20 public token;

  bytes32 public merkleRoot;

  mapping(address => bool) public hasClaimed;

  event Claim(address indexed to, uint256 amount);


  constructor(address _token) {
    token = IERC20(_token);
  }
    
  function initialize(bytes32 _merkleRoot) external initializer returns (bool) {
    merkleRoot = _merkleRoot;
    return true;
  }


  function claim(address to, uint256 amount, bytes32[] calldata proof) external returns (bool) {
    require(!hasClaimed[to], "ClaimerGDX: Already claimed");
    require(proof.length > 0, "ClaimerGDX: Invalid proofs length");

    bytes32 leaf = keccak256(abi.encodePacked(to, amount));

    require(MerkleProof.verify(proof, merkleRoot, leaf), "ClaimerGDX: Invalid proofs");
  
    hasClaimed[to] = true;
    token.safeTransfer(to, amount);

    emit Claim(to, amount);

    return true;
  }

  function foreignTokensRecover(IERC20 _token, uint256 _amount, address _to) external onlyOwner returns (bool) {
    _token.safeTransfer(_to, _amount);
    return true;
  }
}

