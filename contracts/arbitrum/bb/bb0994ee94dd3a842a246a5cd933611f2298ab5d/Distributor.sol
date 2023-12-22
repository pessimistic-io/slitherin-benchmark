// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.9;

import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeERC20.sol";
import "./MerkleProof.sol";

contract Distributor is OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant INIT_CLAIM = 70_750_200_000 * 1e18;
    uint256 public constant TOTAL_CLAIMABLE = 138_000_000_000_000 * 1e18;

    event Claim(address indexed user, uint256 amount, address referrer);

    IERC20 public token;
    bytes32 public merkleRoot;

    mapping(address => bool) public claimedUser;
    mapping(address => uint256) public inviteRewards;

    uint256 public claimedSupply;
    mapping(address => uint256) public inviteUsers;

    function initialize(bytes32 root_, IERC20 token_) external initializer {
        __Ownable_init();
        merkleRoot = root_;
        token = token_;
    }

    function updateRoot(bytes32 root_) external onlyOwner {
        merkleRoot = root_;
    }

    function claimable() public view returns(uint256) {
        uint256 supplyPerAddress = INIT_CLAIM;
        uint256 claimedPercent = percentClaimed();

        //decay 20% every 5% claim
        for(uint8 i; i < claimedPercent / 5e6; ++i) // decay = claimedPercent / 5e6
            supplyPerAddress = supplyPerAddress * 80 / 100;

        return supplyPerAddress;
    }

    function canClaim(bytes32[] calldata merkleProof, address user) public view returns(bool){
        return MerkleProof.verify(merkleProof, merkleRoot, keccak256(abi.encodePacked(user)));
    }

    function claim(bytes32[] calldata merkleProof, address referrer) public {
        require(claimedUser[msg.sender] == false, "already claimed");
        // require(claimedSupply < TOTAL_CLAIMABLE, 'Distributor: Airdrop ended');
        require(MerkleProof.verify(merkleProof, merkleRoot, keccak256(abi.encodePacked(msg.sender))), "Distributor: invalid proof");

        claimedUser[msg.sender] = true;

        uint256 amount = claimable();
        require(token.balanceOf(address(this)) > amount, "Distributor: Airdrop has ended");
        require(amount >= 1e18, "Distributor: Airdrop has ended");

        token.transfer(msg.sender, amount);

        claimedSupply += amount;

        if (referrer != address(0) && referrer != msg.sender) {
            uint256 num = amount * 100 / 1000;
            token.transfer(referrer, num);
            inviteRewards[referrer] += num;
            ++inviteUsers[referrer];
        }

        emit Claim(msg.sender, amount, referrer);
    }

    function hasClaimed(address user) public view returns(bool){
        return claimedUser[user];
    }

    function percentClaimed() public view returns(uint){
        return claimedSupply * 100e6 / TOTAL_CLAIMABLE; 
    }

    function recoverToken(address[] calldata tokens) external onlyOwner {
        unchecked {
            for (uint8 i; i < tokens.length; ++i) {
                IERC20(tokens[i]).safeTransfer(msg.sender, IERC20(tokens[i]).balanceOf(address(this)));
            }
        }
    }
    
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
