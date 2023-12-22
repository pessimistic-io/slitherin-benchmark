//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./MerkleProof.sol";
import "./Counters.sol";

contract AienAirdrop is Ownable {

    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    mapping(address => bool) public claimed;
    bytes32 public merkleRoot;
    IERC20  public claimToken;
    uint public amountPerClaim;
    Counters.Counter private currClaim;
    uint private claimLimit;
    bool public paused;


    function resetAirdrop(address _claimToken, bytes32 _merkleRoot, uint _amountPerClaim, uint _claimLimit) public onlyOwner {
        claimToken = IERC20(_claimToken);
        merkleRoot = _merkleRoot;
        amountPerClaim = _amountPerClaim;
        claimLimit = _claimLimit;
        currClaim.reset();
    }


    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function togglePause() external onlyOwner {
        paused = !paused;
    }

    modifier isValidMerkleProof(bytes32[] calldata _merkleProof, bytes32 _root) {
        require(
            MerkleProof.verify(
                _merkleProof,
                _root,
                keccak256(abi.encodePacked(msg.sender))
            ),
            "Address does not exist in list"
        );
        _;
    }

    function claimProgress() public view returns (uint, uint, bool){
        return (currClaim.current(), claimLimit, claimed[msg.sender]);
    }

    function claim(bytes32[] calldata _merkleProof)
    external
    isValidMerkleProof(_merkleProof, merkleRoot)
    {
        require(!paused, "Pause");
        require(currClaim.current() < claimLimit, "Already ended");
        require(!claimed[msg.sender], "Address already claimed");
        claimed[msg.sender] = true;
        currClaim.increment();
        claimToken.safeTransfer(msg.sender, amountPerClaim);
    }


    function rescueToken(address _tokenAddress) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(msg.sender, IERC20(_tokenAddress).balanceOf(address(this)));
    }

}
