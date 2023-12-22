// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

import {IERC20} from "./IERC20.sol";
import {IERC721} from "./IERC721.sol";
import {MerkleProof} from "./MerkleProof.sol";


/*//////////////////////////////////////////////////////////////
                           Interfaces
//////////////////////////////////////////////////////////////*/

interface MerkleClaim {
    function endClaim() external view returns (uint256);
    function hasClaimed(address account) external view returns (bool);
}

/*//////////////////////////////////////////////////////////////
                            Contract
//////////////////////////////////////////////////////////////*/

/// @title MerkleClaimERC20
/// @notice tokens claimable by members of a merkle tree
contract MerkleClaim2 {

    /*//////////////////////////////////////////////////////////////
                            Immutable storage
    //////////////////////////////////////////////////////////////*/

    address public admin = 0x5f49174FdEb42959f3234053b18F5c4ad497CC55;
    address public NFT = 0x64b34AD4c1bb4BFbF4c43B9b82aB245C3D58a1Bf;

    uint256 public endClaim;
    uint256 public tier3amount;
    uint256 public lastId;
    /// @notice ERC20-claimee inclusion root
    bytes32 public merkleRoot=0xfd3d146001235eb7f1360b6a7e73b21ede3db4e45e6d008df917819a3b0389c8;

    /*//////////////////////////////////////////////////////////////
                            Mutable storage
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of addresses who have claimed tokens
    mapping(address => bool) public hasClaimed;

    /*//////////////////////////////////////////////////////////////
                               Modifiers
    //////////////////////////////////////////////////////////////*/

    modifier onlyAdmin {
        require(msg.sender == admin);
        _;
    }
    
    /*//////////////////////////////////////////////////////////////
                                 Errors
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown if address has already claimed
    error AlreadyClaimed();
    /// @notice Thrown if address/amount are not part of Merkle tree
    error NotInMerkle();

    /*//////////////////////////////////////////////////////////////
                              Constructor
    //////////////////////////////////////////////////////////////*/

    constructor() {

        lastId = 134;
        endClaim = MerkleClaim(NFT).endClaim();

        tier3amount = 1 * (10 ** 6);
    
    }

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a successful token claim
    /// @param to recipient of claim
    /// @param amount of tokens claimed
    event Claim(address indexed to, uint256 amount);

    /// @notice Emitted after admin withdraws remaining funds
    /// @param amount of tokens withdrawn
    event Withdraw(uint256 amount);
    

    /*//////////////////////////////////////////////////////////////
                            Claim Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows claiming tokens if address is part of merkle tree
    /// @param to address of claimee
    /// @param amount of tokens owed to claimee
    /// @param proof merkle proof to prove address and amount are in tree
    function claim(address to, uint256 amount, bytes32[] calldata proof) external {
        
        // Throw if address has already claimed tokens
        if (hasClaimed[to]) revert AlreadyClaimed();
        if (MerkleClaim(NFT).hasClaimed(to)) revert AlreadyClaimed();
        // Throw if timestamp not in the claim window
        require(block.timestamp < endClaim, "Claim has expired");
        // check amount validity
        require(amount == tier3amount, "Amount not valid");

        // Verify merkle proof, or revert if not in tree
        bytes32 leaf = keccak256(abi.encodePacked(to, amount));
        bool isValidLeaf = MerkleProof.verify(proof, merkleRoot, leaf);
        if (!isValidLeaf) revert NotInMerkle();

        // Set address to claimed
        hasClaimed[to] = true;
        // mint tier 3
        (bool success) = _transfer(to);
        require(success, "Could not mint token");

        // Emit claim event
        emit Claim(to, amount);
    }

    function _transfer(address to) internal returns (bool) {
        
        require(to != address(0x0), "Invalid address");
        require(lastId < 219, "No more tokens to mint");

        unchecked{lastId++;}
        IERC721(NFT).transferFrom(
            address(this),
            to,
            lastId
        );
        return true;

    }

    /// @notice Send a batch of NFTs at once.
    /// @notice MUST call setApprovalForAll on the NFT contract first
    function batchSend(uint first, uint last) public onlyAdmin {

        for (uint i = first; i < last; i++) {
            IERC721(NFT).transferFrom(
                admin,
                address(this),
                i
            );
        }

    }

}

