pragma solidity =0.8.0;

import "./IERC20.sol";
import "./MerkleProof.sol";
import "./Ownable.sol";

/**
 * Slightly modified version of: https://github.com/Uniswap/merkle-distributor/blob/master/contracts/MerkleDistributor.sol
 * Changes include:
 * - remove "./interfaces/IMerkleDistributor.sol" inheritance
 * - Contract name and require statement message string changes
 * - add withdrawBlock and withdrawAddress state variables and withdraw() method
 */
contract dGenesisVaultClaim is Ownable {


    struct Claim {
    address token;
    bytes32 merkleRoot;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) claimedBitMap;
    }
    uint256 public nextProjectId = 1;
    mapping(uint256 => Claim) claims;
    
    

    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(uint256 claimIndex, uint256 index, address account, uint256 amount);



    function addClaim (address _token, bytes32 _merkleRoot) public onlyOwner returns (uint256) {
        
        claims[nextProjectId].token = _token;
        claims[nextProjectId].merkleRoot = _merkleRoot;
        nextProjectId = nextProjectId + 1;
        return nextProjectId;
    }

    function isClaimed(uint256 claimIndex, uint256 index) public view returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claims[claimIndex].claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 claimIndex, uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claims[claimIndex].claimedBitMap[claimedWordIndex] = claims[claimIndex].claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
    }

    /**
     * No caller permissioning needed since token is transfered to account argument,
     *    and there is no incentive to call function for another account.
     * Can only submit claim for full claimable amount, otherwise proof verification will fail.
     */
    function claim(uint256 claimIndex, uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external {
        require(!isClaimed(claimIndex, index), 'dGenesisVaultClaim: Drop already claimed.');

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(MerkleProof.verify(merkleProof, claims[claimIndex].merkleRoot, node), 'dGenesisVaultClaim: Invalid proof.');

        // Mark it claimed and send the token.
        _setClaimed(claimIndex, index);
        require(IERC20(claims[claimIndex].token).transfer(account, amount), 'dGenesisVaultClaim: Transfer failed.');

        emit Claimed(claimIndex, index, account, amount);
    }

    function withdraw(address _token) external onlyOwner {

        require(
            IERC20(_token).transfer(msg.sender, IERC20(_token).balanceOf(address(this))),
            'dGenesisVaultClaim: Withdraw transfer failed.'
        );
    }
}
