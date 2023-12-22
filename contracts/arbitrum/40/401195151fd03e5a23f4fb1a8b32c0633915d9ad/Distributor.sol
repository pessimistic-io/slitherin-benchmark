// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.19;

import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeERC20.sol";
import "./MerkleProof.sol";

contract Distributor is OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_ADDRESSES = 180000;
    uint256 public constant INIT_CLAIM = 200_000_000 * 1e9;

    struct InfoView {
        uint256 initClaim;
        uint256 currentClaim;
        bool claimed;
        uint256 inviteRewards;
        uint256 inviteUsers;
        uint256 claimedSupply;
        uint256 claimedCount;
    }

    event Claim(address indexed user, uint256 amount, address referrer);

    IERC20 public token;
    bytes32 public merkleRoot;

    mapping(address => bool) public claimedUser;
    mapping(address => uint256) public inviteRewards;

    uint256 public claimedSupply;
    uint256 public claimedCount;
    uint256 public claimedPercentage;
    mapping(address => uint256) public inviteUsers;

    constructor() initializer {}

    function initialize(bytes32 root_, IERC20 token_) external initializer {
        __Ownable_init();
        merkleRoot = root_;
        token = token_;
    }

    function updateRoot(bytes32 root_) external onlyOwner {
        merkleRoot = root_;
    }

    function claimable() public view returns(uint256) {
        if (claimedCount >= MAX_ADDRESSES) {
            return 0;
        }

        uint256 supplyPerAddress = INIT_CLAIM;
        uint256 curClaimedCount = claimedCount + 1;
        uint256 claimedPercent = curClaimedCount * 100e6 / MAX_ADDRESSES;

        //decay 20% every 5% claim
        for(uint8 i; i < claimedPercent / 5e6; ++i) // decay = claimedPercent / 5e6
            supplyPerAddress = supplyPerAddress * 80 / 100;

        return supplyPerAddress;
    }

    // only for test
    function setClaimedAddress(uint amount) external onlyOwner{
       claimedCount = amount;
    }

    function claim(bytes32[] calldata merkleProof, address referrer) public {
        require(claimedUser[msg.sender] == false, "already claimed");
        require(MerkleProof.verify(merkleProof, merkleRoot, keccak256(abi.encodePacked(msg.sender))), "invalid proof");

        claimedUser[msg.sender] = true;

        uint256 amount = claimable();
        require(amount >= 1e9, "airdrop has ended");

        token.transfer(msg.sender, amount);

        claimedCount++;
        claimedSupply += amount;

        if (claimedCount > 0) {
            claimedPercentage = (claimedCount * 100) / MAX_ADDRESSES;
        }

        if (referrer != address(0) && referrer != msg.sender) {
            uint256 num = amount * 100 / 1000;
            token.transfer(referrer, num);
            inviteRewards[referrer] += num;
            ++inviteUsers[referrer];
        }

        emit Claim(msg.sender, amount, referrer);
    }

    function getInfoView(address user) public view returns(InfoView memory) {
        return InfoView({
            initClaim: INIT_CLAIM,
            currentClaim: claimable(),
            claimed: claimedUser[user],
            inviteRewards: inviteRewards[user],
            inviteUsers: inviteUsers[user],
            claimedSupply: claimedSupply,
            claimedCount: claimedCount
        });
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
