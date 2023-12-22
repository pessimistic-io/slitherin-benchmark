// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./Ownable.sol";
import "./IERC20.sol";

interface IDogeClaim {
    function _claimedUser() external view returns (bool);
}

interface IRewardPool {
    function deposit(uint256 _pid, uint256 _amount) external;
}

contract DistributionPool is Ownable {
    uint256 public constant MAX_ADDRESSES = 625_143;
    uint256 public constant INIT_CLAIM = 1434 * 1e6;
    address public constant ARB_TOKEN =
        0x912CE59144191C1204E64559FE8253a0e49E6548;
    address public constant AIDOGECLAIM =
        0x7c20acfd25467dE0B92d03E4C4d304f18B8408E1;

    address public rewardPool;
    address public noFoMoToken;

    struct InfoView {
        uint256 initClaim;
        uint256 currentClaim;
        bool claimed;
        uint256 inviteRewards;
        uint256 inviteUsers;
        uint256 claimedSupply;
        uint256 claimedCount;
    }

    mapping(address => bool) public isClaimedAddress;
    mapping(address => uint256) public inviteRewards;

    uint256 public claimedSupply = 0;
    uint256 public claimedCount = 0;
    uint256 public claimedPercentage = 0;
    mapping(address => uint256) public inviteUsers;

    function canClaimAmount() public view returns (uint256) {
        if (claimedCount >= MAX_ADDRESSES) {
            return 0;
        }

        uint256 supplyPerAddress = INIT_CLAIM;
        uint256 curClaimedCount = claimedCount + 1;
        uint256 claimedPercent = (curClaimedCount * 100e6) / MAX_ADDRESSES;
        uint256 curPercent = 5e6;

        while (curPercent <= claimedPercent) {
            supplyPerAddress = (supplyPerAddress * 80) / 100;
            curPercent += 5e6;
        }

        return supplyPerAddress;
    }

    function claim(address referrer) public {
        require(
            IERC20(ARB_TOKEN).balanceOf(msg.sender) >= 1e18 ||
                IDogeClaim(AIDOGECLAIM)._claimedUser(),
            "Not Qualified"
        );
        require(isClaimedAddress[msg.sender] == false, "Already Claimed");
        isClaimedAddress[msg.sender] = true;
        claimedCount++;

        uint256 claimedAmount = canClaimAmount();
        require(claimedAmount >= 1e6, "Airdrop has ended");

        IERC20(noFoMoToken).transfer(msg.sender, claimedAmount);
        claimedSupply += claimedAmount;

        if (claimedCount > 0) {
            claimedPercentage = (claimedCount * 100) / MAX_ADDRESSES;
        }

        if (referrer != address(0) && referrer != _msgSender()) {
            uint256 num = (claimedAmount * 100) / 1000;
            IERC20(noFoMoToken).transfer(referrer, num);
            inviteRewards[referrer] += num;
            inviteUsers[referrer]++;
        }
    }

    function setRewardPool(address _rewardPool) external onlyOwner {
        rewardPool = _rewardPool;
    }

    function setNoFomoTOKEN(address _noFomoToken) external onlyOwner {
        noFoMoToken = _noFomoToken;
    }

    function getInfoView(address user) public view returns (InfoView memory) {
        return
            InfoView({
                initClaim: INIT_CLAIM,
                currentClaim: canClaimAmount(),
                claimed: isClaimedAddress[user],
                inviteRewards: inviteRewards[user],
                inviteUsers: inviteUsers[user],
                claimedSupply: claimedSupply,
                claimedCount: claimedCount
            });
    }
}

