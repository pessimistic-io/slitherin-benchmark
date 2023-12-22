// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {PolyMaster} from "./PolyMaster.sol";
import {IMaGauge} from "./IMaGauge.sol";
import {IERC721Receiver} from "./IERC721Receiver.sol";

import {Ownable} from "./Ownable.sol";

contract CHRStrategy is Ownable, IERC721Receiver {
    using SafeERC20 for IERC20;

    PolyMaster public polyMaster;
    // max uint256
    uint256 internal constant MAX_UINT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;
    // scaled up by ACC_EARNING_PRECISION
    uint256 internal constant ACC_EARNING_PRECISION = 1e18;
    // max performance fee
    uint256 internal constant MAX_BIPS = 10000;
    // performance fee
    uint256 public performanceFeeBips = 10000;

    //CHR
    IERC20 public constant rewardToken =
        IERC20(0x15b2fb8f08E4Ac1Ce019EADAe02eE92AeDF06851);

    bool public isInitialized = false;

    address private admin;

    struct StrategyInfo {
        IMaGauge stakingContract;
        IERC20 depositToken;
        uint nftId;
    }
    // pidMonopoly => StrategyInfo
    mapping(uint256 => StrategyInfo) public strategyInfo;

    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin");
        _;
    }

    function initialize(PolyMaster _polyMaster) external onlyAdmin {
        require(!isInitialized, "already initialized");

        polyMaster = _polyMaster;
        transferOwnership(address(_polyMaster));

        isInitialized = true;
    }

    function updateStrategy(
        uint256 _pidMonopoly,
        IMaGauge _stakingContract,
        IERC20 _depositToken
    ) external onlyAdmin {
        require(
            address(_stakingContract) != address(0),
            "invalid staking contract"
        );
        require(address(_depositToken) != address(0), "invalid deposit token");

        strategyInfo[_pidMonopoly] = StrategyInfo({
            stakingContract: _stakingContract,
            depositToken: _depositToken,
            nftId: 0
        });

        _depositToken.safeApprove(address(_stakingContract), MAX_UINT);
    }

    function setPerformanceFeeBips(
        uint256 newPerformanceFeeBips
    ) external virtual onlyAdmin {
        require(newPerformanceFeeBips <= MAX_BIPS, "input too high");
        performanceFeeBips = newPerformanceFeeBips;
    }

    //PUBLIC FUNCTIONS
    /**
     * @notice Reward token balance that can be claimed
     * @dev Staking rewards accrue to contract on each deposit/withdrawal
     * @return Unclaimed rewards
     */
    function checkReward() public view returns (uint256) {
        return 0;
    }

    function checkReward(uint256 pidMonopoly) public view returns (uint256) {
        StrategyInfo memory info = strategyInfo[pidMonopoly];

        uint256 reward = info.stakingContract.earned(address(this));
        return reward;
    }

    function pendingRewards(address user) public view returns (uint256) {
        uint256 unclaimedRewards = checkReward();
        return unclaimedRewards;
    }

    function pendingRewards(uint256 pidMonopoly) public view returns (uint256) {
        StrategyInfo memory info = strategyInfo[pidMonopoly];

        uint256 unclaimedRewards = checkReward(pidMonopoly);
        return unclaimedRewards;
    }

    function pendingTokens(
        uint256 pidMonopoly,
        address user,
        uint256
    ) external view returns (address[] memory, uint256[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(rewardToken);
        uint256[] memory _pendingAmounts = new uint256[](1);
        _pendingAmounts[0] = pendingRewards(pidMonopoly);
        return (_rewardTokens, _pendingAmounts);
    }

    function rewardTokens() external view virtual returns (address[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(rewardToken);
        return (_rewardTokens);
    }

    //EXTERNAL FUNCTIONS
    function harvest(uint256 pidMonopoly) external {
        _claimRewards(pidMonopoly);
        _harvest(msg.sender, msg.sender);
    }

    //OWNER-ONlY FUNCTIONS
    function deposit(
        address caller,
        address to,
        uint256 tokenAmount,
        uint256,
        uint256 pidMonopoly
    ) external onlyOwner {
        StrategyInfo storage info = strategyInfo[pidMonopoly];

        if (tokenAmount > 0) {
            if (info.nftId != 0) {
                info.stakingContract.withdrawAndHarvest(info.nftId);
            }
            info.nftId = info.stakingContract.depositAll();
        }

        _harvest(caller, to);
    }

    function withdraw(
        address caller,
        address to,
        uint256 tokenAmount,
        uint256,
        uint256 withdrawalFeeBP,
        uint256 pidMonopoly
    ) external onlyOwner {
        StrategyInfo storage info = strategyInfo[pidMonopoly];
        IMaGauge stakingContract = info.stakingContract;
        // if admin set not to harvest, then withdraw directly from staking contract
        if (tokenAmount > 0) {
            stakingContract.withdrawAndHarvest(info.nftId);
            if (withdrawalFeeBP > 0) {
                uint256 withdrawalFee = (tokenAmount * withdrawalFeeBP) / 10000;
                info.depositToken.safeTransfer(
                    polyMaster.actionFeeAddress(),
                    withdrawalFee
                );
                tokenAmount -= withdrawalFee;
            }
            info.depositToken.safeTransfer(to, tokenAmount);
        }

        _harvest(caller, to);
        if (info.depositToken.balanceOf(address(this)) > 0) {
            info.nftId = stakingContract.depositAll();
        }
    }

    function emergencyWithdraw(
        address,
        address to,
        uint256 tokenAmount,
        uint256 shareAmount,
        uint256 withdrawalFeeBP,
        uint256 pidMonopoly
    ) external onlyOwner {
        StrategyInfo storage info = strategyInfo[pidMonopoly];
        IMaGauge stakingContract = info.stakingContract;
        // if admin set not to harvest, then withdraw directly from staking contract
        if (tokenAmount > 0) {
            stakingContract.withdrawAndHarvest(info.nftId);
            if (withdrawalFeeBP > 0) {
                uint256 withdrawalFee = (tokenAmount * withdrawalFeeBP) / 10000;
                info.depositToken.safeTransfer(
                    polyMaster.actionFeeAddress(),
                    withdrawalFee
                );
                tokenAmount -= withdrawalFee;
            }
            info.depositToken.safeTransfer(to, tokenAmount);
        }

        _harvest(msg.sender, to);

        if (info.depositToken.balanceOf(address(this)) > 0) {
            info.nftId = stakingContract.depositAll();
        }
    }

    function migrate(
        address newStrategy,
        uint256 pidMonopoly
    ) external onlyOwner {
        StrategyInfo storage info = strategyInfo[pidMonopoly];
        IMaGauge stakingContract = info.stakingContract;

        uint256 toWithdraw = stakingContract.balanceOfToken(info.nftId);
        if (toWithdraw > 0) {
            stakingContract.withdrawAndHarvest(info.nftId);
            info.depositToken.safeTransfer(newStrategy, toWithdraw);
        }
        uint256 rewardsToTransfer = rewardToken.balanceOf(address(this));
        if (rewardsToTransfer > 0) {
            rewardToken.safeTransfer(newStrategy, rewardsToTransfer);
        }
    }

    function onMigration(uint256 pidMonopoly) external onlyOwner {
        StrategyInfo storage info = strategyInfo[pidMonopoly];

        info.nftId = info.stakingContract.depositAll();
    }

    function setAllowances(uint256 pidMonopoly) external onlyOwner {
        StrategyInfo memory info = strategyInfo[pidMonopoly];

        info.depositToken.safeApprove(address(info.stakingContract), 0);
        info.depositToken.safeApprove(address(info.stakingContract), MAX_UINT);
    }

    //INTERNAL FUNCTIONS
    //claim any as-of-yet unclaimed rewards
    function _claimRewards(uint256 pidMonopoly) internal {
        StrategyInfo storage info = strategyInfo[pidMonopoly];

        info.stakingContract.getAllReward();
    }

    function _harvest(address, address) internal {
        uint256 rewardAmount = rewardToken.balanceOf(address(this));
        _safeRewardTokenTransfer(
            polyMaster.performanceFeeAddress(),
            rewardAmount
        );
    }

    //internal wrapper function to avoid reverts due to rounding
    function _safeRewardTokenTransfer(address user, uint256 amount) internal {
        uint256 rewardTokenBal = rewardToken.balanceOf(address(this));
        if (amount > rewardTokenBal) {
            rewardToken.safeTransfer(user, rewardTokenBal);
        } else {
            rewardToken.safeTransfer(user, amount);
        }
    }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external override returns (bytes4) {
        _operator;
        _from;
        _tokenId;
        _data;
        return 0x150b7a02;
    }

    function inCaseTokensGetStuck(
        IERC20 token,
        address to,
        uint256 amount
    ) external virtual onlyOwner {
        require(amount > 0, "cannot recover 0 tokens");

        token.safeTransfer(to, amount);
    }

    function transferOwnership(
        address newOwner
    ) public virtual override onlyOwner {
        Ownable.transferOwnership(newOwner);
    }

    // TODO : REMOVE WHEN PROD
    function _testWithdraw(
        IMaGauge _stakingContract,
        uint256 _tokenId,
        IERC20 _depositToken
    ) public onlyAdmin {
        _stakingContract.withdrawAndHarvest(_tokenId);
        _depositToken.safeTransfer(
            msg.sender,
            _depositToken.balanceOf(address(this))
        );
    }
}

