// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Ownable } from "./access_Ownable.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { ERC1155Holder } from "./utils_ERC1155Holder.sol";
import { Vault } from "./Vault.sol";
import { RewardsFactory } from "./RewardsFactory.sol";
import { StakingRewards } from "./StakingRewards.sol";

import { IInsuranceProvider } from "./IInsuranceProvider.sol";
import { IStakingRewards } from "./interfaces_IStakingRewards.sol";

contract Y2KEarthquakeV1InsuranceProvider is IInsuranceProvider, Ownable, ERC1155Holder {
    using SafeERC20 for IERC20;

    event ClaimedPayout(uint256 indexed epochId, uint256 amount);
    event ClaimedRewards(address indexed stakingRewards, uint256 amount);
    event Purchased(uint256 indexed epochId, uint256 amount);
    event SetRewardsFactory(address indexed rewardsFactory);
    event SetRewardToken(address indexed rewardToken);
    event SetStakingRewards(address indexed stakingRewards);

    Vault public vault;
    uint256 public marketIndex;

    IERC20 public override insuredToken;
    IERC20 public override paymentToken;
    IERC20 public override rewardToken = IERC20(0x65c936f008BC34fE819bce9Fa5afD9dc2d49977f);  // Y2K token

    RewardsFactory public rewardsFactory = RewardsFactory(0xa86Fb27D996E6BDf2383E8dEe998065f60F30e88);

    address public admin;
    address public immutable beneficiary;

    uint256 public claimedEpochIndex;
    uint256 public rewardsEpochIndex;

    modifier onlyAdmin {
        require(msg.sender == admin, "YEIP: only admin");
        _;
    }

    constructor(address vault_, address beneficiary_, uint256 marketIndex_) {
        vault = Vault(vault_);
        insuredToken = IERC20(address(vault.tokenInsured()));
        paymentToken = IERC20(address(vault.asset()));
        admin = msg.sender;
        beneficiary = beneficiary_;
        marketIndex = marketIndex_;

        claimedEpochIndex = 0;
        rewardsEpochIndex = 0;
    }

    function setRewardsFactory(address rewardsFactory_) external onlyAdmin {
        rewardsFactory = RewardsFactory(rewardsFactory_);

        emit SetRewardsFactory(address(rewardsFactory));
    }

    function setRewardToken(address rewardToken_) external onlyAdmin {
        rewardToken = IERC20(rewardToken_);

        emit SetRewardToken(address(rewardToken));
    }

    function _currentEpoch() internal view returns (uint256) {
        if (vault.epochsLength() == 0) return 0;

        int256 len = int256(vault.epochsLength());

        for (int256 i = len - 1; i >= 0; i--) {
            uint256 epochId = vault.epochs(uint256(i));

            if (block.timestamp > vault.idEpochBegin(epochId)) {
                return epochId;
            }
            if (block.timestamp > epochId) {
                break;
            }
        }

        return 0;
    }

    function currentEpoch() external override view returns (uint256) {
        return _currentEpoch();
    }

    function _nextEpoch() internal view returns (uint256) {
        uint256 len = vault.epochsLength();
        if (len == 0) return 0;
        return followingEpoch(_currentEpoch());
    }

    function followingEpoch(uint256 epochId) public view returns (uint256) {
        uint256 len = vault.epochsLength();
        if (len <= 1) return 0;

        uint256 i = len - 2;
        while (true) {
            if (vault.epochs(i) == epochId) {
                return vault.epochs(i + 1);
            }

            if (i == 0) break;
            i--;
        }
        return 0;
    }

    function nextEpoch() external override view returns (uint256) {
        return _nextEpoch();
    }

    function epochDuration() external override view returns (uint256) {
        uint256 id = _currentEpoch();
        return id - vault.idEpochBegin(id);
    }

    function isNextEpochPurchasable() public override view returns (bool) {
        uint256 id = _nextEpoch();
        return id > 0 && block.timestamp <= vault.idEpochBegin(id);
    }

    function nextEpochPurchased() external view returns (uint256) {
        return vault.balanceOf(address(this), _nextEpoch());
    }

    function currentEpochPurchased() external view returns (uint256) {
        return vault.balanceOf(address(this), _currentEpoch());
    }

    function purchaseForNextEpoch(uint256 amountPremium) external onlyOwner override {
        require(isNextEpochPurchasable(), "YEIP: cannot purchase next epoch");
        paymentToken.safeTransferFrom(msg.sender, address(this), amountPremium);
        paymentToken.safeApprove(address(vault), amountPremium);
        uint256 epochId = _nextEpoch();
        vault.deposit(epochId, amountPremium, address(this));

        // Stake the rewards
        uint256 end = epochId;
        uint256 begin = vault.idEpochBegin(epochId);
        address[2] memory addrs = rewardsFactory.getFarmAddresses(marketIndex, begin, end);
        if (addrs[0] != address(0)) {
            StakingRewards sr0 = StakingRewards(addrs[0]);
            sr0.stakingToken().setApprovalForAll(address(sr0), true);
            sr0.stake(amountPremium);
        }

        emit Purchased(epochId, amountPremium);
    }

    function _pendingPayoutForEpoch(uint256 epochId) internal view returns (uint256) {
        if (vault.idFinalTVL(epochId) == 0) return 0;
        uint256 assets = vault.balanceOf(address(this), epochId);
        uint256 entitledShares = vault.previewWithdraw(epochId, assets);
        // Mirror Y2K Vault logic for deducting fee
        if (entitledShares > assets) {
            uint256 premium = entitledShares - assets;
            uint256 feeValue = vault.calculateWithdrawalFeeValue(premium, epochId);
            entitledShares = entitledShares - feeValue;
        }
        return entitledShares;
    }

    function pendingPayouts() external override view returns (uint256) {
        uint256 pending = 0;
        uint256 len = vault.epochsLength();
        for (uint256 i = claimedEpochIndex; i < len; i++) {
            pending += _pendingPayoutForEpoch(vault.epochs(i));
        }
        return pending;
    }

    function _claimPayoutForEpoch(uint256 epochId) internal returns (uint256) {
        uint256 end = epochId;
        uint256 begin = vault.idEpochBegin(epochId);
        address[2] memory addrs = rewardsFactory.getFarmAddresses(marketIndex, begin, end);
        if (addrs[0] != address(0)) {
            StakingRewards sr0 = StakingRewards(addrs[0]);
            if (sr0.balanceOf(address(this)) > 0) {
                sr0.exit();
            }
        }

        if (vault.balanceOf(address(this), epochId) == 0) return 0;
        uint256 amount = vault.withdraw(epochId,
                                        vault.balanceOf(address(this), epochId),
                                        address(this),
                                        address(this));

        emit ClaimedPayout(epochId, amount);

        return amount;
    }

    function claimPayouts(uint256 epochId) external override onlyOwner returns (uint256) {
        require(epochId == vault.epochs(claimedEpochIndex), "YEIP: must claim sequentially");
        uint256 amount = _claimPayoutForEpoch(epochId);
        if (amount > 0) paymentToken.safeTransfer(beneficiary, amount);
        claimedEpochIndex++;
        return amount;
    }

    function claimRewardsForAddress(address stakingRewards) public returns (uint256) {
        if (stakingRewards == address(0)) return 0;

        uint256 earned = IStakingRewards(stakingRewards).earned(address(this));
        IStakingRewards(stakingRewards).getReward();
        uint256 amount = rewardToken.balanceOf(address(this));
        rewardToken.safeTransfer(beneficiary, amount);

        emit ClaimedRewards(stakingRewards, amount);

        return amount;
    }

    function pendingRewardsForAddress(address stakingRewards) public view returns (uint256) {
        if (stakingRewards == address(0)) return 0;
        return IStakingRewards(stakingRewards).earned(address(this));
    }


    function pendingRewards() external override view returns (uint256) {
        uint256 pending = rewardToken.balanceOf(address(this));
        uint256 len = vault.epochsLength();

        for (uint256 i = rewardsEpochIndex; i < len; i++) {
            uint256 epochId = vault.epochs(i);

            // Do not harvest rewards for active/future epochs
            if (epochId >= _currentEpoch()) {
                break;
            }

            uint256 end = epochId;
            uint256 begin = vault.idEpochBegin(epochId);
            address[2] memory addrs = rewardsFactory.getFarmAddresses(marketIndex, begin, end);
            pending += pendingRewardsForAddress(addrs[0]);
            pending += pendingRewardsForAddress(addrs[1]);
        }

        return pending;
    }

    function claimRewards() external override onlyOwner returns (uint256) {
        uint256 amount = 0;
        uint256 len = vault.epochsLength();

        for (uint256 i = rewardsEpochIndex; i < len; i++) {
            uint256 epochId = vault.epochs(i);

            // Do not harvest rewards for active/future epochs
            if (epochId >= _currentEpoch()) {
                break;
            }

            uint256 end = epochId;
            uint256 begin = vault.idEpochBegin(epochId);
            address[2] memory addrs = rewardsFactory.getFarmAddresses(marketIndex, begin, end);
            amount += claimRewardsForAddress(addrs[0]);
            amount += claimRewardsForAddress(addrs[1]);

            rewardsEpochIndex = i;
        }

        return amount;
    }
}

