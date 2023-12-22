// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./MerkleProof.sol";
import "./SafeERC20.sol";
import "./Initializable.sol";


interface IVesterRewardPool {  
    function stakeForAccount(address account, uint256 amount) external returns (bool);
}


contract ClaimerUSDEX is Ownable, Initializable {
  using SafeERC20 for IERC20;

  uint256 public constant DIVISOR = 10000;

  IERC20 public primeToken;
  IERC20 public escrowToken;

  address public pool;

  bytes32 public merkleRoot;

  uint256 public distributionCoeff;

  mapping(address => bool) public hasClaimed;

  event Claim(address indexed to, address indexed primeToken, uint256 primeTokenAmount, address indexed escrowToken, uint256 escrowTokenAmount);


  constructor(address _primeToken, address _escrowToken) {
    primeToken = IERC20(_primeToken);
    escrowToken = IERC20(_escrowToken);
  }
    
  function initialize(bytes32 _merkleRoot, uint256 _distributionCoeff, address _pool) external initializer returns (bool) {
    require(_distributionCoeff <= DIVISOR, "ClaimerUSDEX: Distribution coefficient gte DIVISOR");
    require(_pool != address(0), "ClaimerUSDEX: Pool is zero address");
    merkleRoot = _merkleRoot;
    distributionCoeff = _distributionCoeff;
    pool = _pool;

    return true;
  }


  function claim(address to, uint256 amount, bytes32[] calldata proof) external returns (bool) {
    require(!hasClaimed[to], "ClaimerUSDEX: Already claimed");
    require(proof.length > 0, "ClaimerUSDEX: Invalid proofs length");

    bytes32 leaf = keccak256(abi.encodePacked(to, amount));

    require(MerkleProof.verify(proof, merkleRoot, leaf), "ClaimerUSDEX: Invalid proofs");
    hasClaimed[to] = true;

    uint256 primeTokenAmount = amount * distributionCoeff / DIVISOR;
    uint256 escrowTokenAmount = amount * (DIVISOR - distributionCoeff) / DIVISOR;

    primeToken.safeTransfer(to, primeTokenAmount);

    escrowToken.approve(address(pool), escrowTokenAmount);
    IVesterRewardPool(pool).stakeForAccount(to, escrowTokenAmount);

    emit Claim(to, address(primeToken), primeTokenAmount, address(escrowToken), escrowTokenAmount);

    return true;
  }

  function foreignTokensRecover(IERC20 _token, uint256 _amount, address _to) external onlyOwner returns (bool) {
    _token.safeTransfer(_to, _amount);
    return true;
  }
}

