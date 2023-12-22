pragma solidity ^0.8.0;
//SPDX-License-Identifier: UNLICENSED

import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./ISignature.sol";

/** 
 * Tales of Elleria - For distributing on-chain ERC20 airdrops.
 * 1. Owner deposits ERC20 into the contract.
 * 2. Owner calls SetupReward with the relevant parameters (amount in WEI)
 * 3. Users can claim through https://app.talesofelleria.com/
*/
contract RewardClaim is ReentrancyGuard {

  struct RewardEntry {
    bytes32 root;
    uint256 royaltyAmount;
    address royaltyAddress;
    mapping (address => bool) isAddressClaimed;
    bool isValid;
    uint256 claimedCount;
  }

  mapping(uint => RewardEntry) rewards;

  address private ownerAddress;             // The contract owner's address.
  ISignature private signatureAbi;
  address private signerAddr;

  constructor() {
        ownerAddress = msg.sender;
    }

    function _onlyOwner() private view {
        require(msg.sender == ownerAddress, "O");
    }

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    // Merkle Proofs
    function setRoot(uint rewardId, bytes32 root) external onlyOwner {
        rewards[rewardId].root = root;
    }

    function verify(uint rewardId, bytes32 leaf, bytes32[] memory proof) public view returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
        bytes32 proofElement = proof[i];

        if (computedHash <= proofElement) {
            // Hash(current computed hash + current element of the proof)
            computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
        } else {
            // Hash(current element of the proof + current computed hash)
            computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
        }
        }

        // Check if the computed hash (root) is equal to the provided root
        return computedHash == rewards[rewardId].root;
    }

    function isWhitelisted(uint rewardId, address addr, bytes32[] memory proof) external view returns (uint) {
        if (rewards[rewardId].isAddressClaimed[addr]) {
            return 2; // Claimed.
        } else if (verify(rewardId, keccak256(abi.encode(addr)), proof)) {
            return 1; // Eligible.
        }
        return 0; // Ineligible.
    }

    function claimedCount(uint rewardId) external view returns (uint256) {
        return rewards[rewardId].claimedCount;
    }

    function royaltyAmount(uint rewardId) external view returns (uint256) {
    return rewards[rewardId].royaltyAmount;
    }

    // Amount specified from snapshot to enable use of proofs with a single wallet holding multiple NFTs.
    function ClaimRoyalty(uint rewardId, uint256 amount, bytes memory signature, bytes32[] memory proof) external nonReentrant {
        require (tx.origin == msg.sender, "RewardClaim: No delegating.");
        require (!(rewards[rewardId].isAddressClaimed[msg.sender]), "RewardClaim: Already Claimed.");
        require (rewards[rewardId].isValid, "RewardClaim: Invalid Reward.");
        require (IERC20(rewards[rewardId].royaltyAddress).balanceOf(address(this)) >= amount, "RewardClaim: Insufficient ERC20 Token.");
        require (amount % rewards[rewardId].royaltyAmount == 0, "RewardClaim: Invalid Amount");
        require (verify(rewardId, keccak256(abi.encode(msg.sender)), proof), "RewardClaim: Invalid Proof.");
        require (signatureAbi.verify(signerAddr, msg.sender, rewardId, "reward claim", amount, signature), "RewardClaim: Invalid Signature.");
    
        IERC20(rewards[rewardId].royaltyAddress).transfer(msg.sender, amount);
        rewards[rewardId].isAddressClaimed[msg.sender] = true;
        rewards[rewardId].claimedCount += amount / rewards[rewardId].royaltyAmount;

        emit RewardClaimed(rewardId, msg.sender, rewards[rewardId].royaltyAddress, amount);
    }

    function setupReward(uint rewardId, bytes32 _root, uint256 _royaltyAmount, address _royaltyAddress) external onlyOwner {
        require (!rewards[rewardId].isValid, "RewardClaim: Cannot change ongoing reward.");

        rewards[rewardId].root = _root;
        rewards[rewardId].royaltyAmount = _royaltyAmount;
        rewards[rewardId].royaltyAddress = _royaltyAddress;
        rewards[rewardId].isValid = true;
    }

    function disableReward(uint rewardId) external onlyOwner {
        rewards[rewardId].isValid = false;
    }

  function setAddresses(address _signatureAddr, address _signerAddr) external onlyOwner {
    signatureAbi = ISignature(_signatureAddr);
    signerAddr = _signerAddr;
  }

  function withdraw() public onlyOwner {
    (bool success, ) = (msg.sender).call{value:address(this).balance}("");
    require(success, "RewardClaim: Invalid Balance.");
  }

  function withdrawERC20(address _erc20Addr, address _recipient) external onlyOwner {
    IERC20(_erc20Addr).transfer(_recipient, IERC20(_erc20Addr).balanceOf(address(this)));
  }

  event RewardClaimed(uint indexed rewardId, address indexed claimedBy, address token, uint256 amount);

}
