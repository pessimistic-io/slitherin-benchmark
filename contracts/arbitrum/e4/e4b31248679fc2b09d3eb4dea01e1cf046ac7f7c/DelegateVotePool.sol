// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./SafeERC20.sol";

import "./ManagerUpgradeable.sol";
import "./TransferHelper.sol";
import "./IBribeManager.sol";
import "./INativeZapper.sol";
import "./IVirtualBalanceRewardPool.sol";

contract DelegateVotePool is ManagerUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using TransferHelper for address;

    address public quo;
    address public bribeManager;
    IVirtualBalanceRewardPool public rewardPool;
    INativeZapper public nativeZapper;

    address public feeCollector;

    uint256 public constant DENOMINATOR = 10000;
    uint256 public protocolFee;

    address[] public votePools;
    mapping(address => bool) public isVotePool;
    mapping(address => uint256) public votingWeights;
    uint256 public totalWeight;

    event QuoHarvested(uint256 _amount, uint256 _fee);

    function initialize() public initializer {
        __ManagerUpgradeable_init();
    }

    function setParams(
        address _quo,
        address _bribeManager,
        address _rewardPool,
        address _nativeZapper,
        address _feeCollector
    ) external onlyOwner {
        require(bribeManager == address(0), "params have already been set");

        require(_quo != address(0), "invalid _quo!");
        require(_bribeManager != address(0), "invalid _bribeManager!");
        require(_rewardPool != address(0), "invalid _rewardPool!");
        require(_nativeZapper != address(0), "invalid _nativeZapper!");
        require(_feeCollector != address(0), "invalid _feeCollector!");

        quo = _quo;
        bribeManager = _bribeManager;
        rewardPool = IVirtualBalanceRewardPool(_rewardPool);
        nativeZapper = INativeZapper(_nativeZapper);
        feeCollector = _feeCollector;

        protocolFee = 500;
    }

    modifier onlyBribeManager() {
        require(msg.sender == bribeManager, "Only BribeManager");
        _;
    }

    modifier harvest() {
        // handle bribes reward
        (
            address[][] memory rewardTokensList,
            uint256[][] memory earnedRewards
        ) = IBribeManager(bribeManager).getRewardAll();
        uint256 quoAmount = 0;
        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            for (uint256 j = 0; j < rewardTokensList[i].length; j++) {
                address rewardToken = rewardTokensList[i][j];
                uint256 earnedReward = earnedRewards[i][j];
                if (rewardToken == address(0) || earnedReward == 0) {
                    continue;
                }
                if (rewardToken == quo) {
                    quoAmount = quoAmount.add(earnedReward);
                    continue;
                }
                if (AddressLib.isPlatformToken(rewardToken)) {
                    quoAmount = quoAmount.add(
                        nativeZapper.swapToken{value: earnedReward}(
                            rewardToken,
                            quo,
                            earnedReward,
                            address(this)
                        )
                    );
                } else {
                    _approveTokenIfNeeded(
                        rewardToken,
                        address(nativeZapper),
                        earnedReward
                    );
                    quoAmount = quoAmount.add(
                        nativeZapper.swapToken(
                            rewardToken,
                            quo,
                            earnedReward,
                            address(this)
                        )
                    );
                }
            }
        }
        if (quoAmount > 0) {
            uint256 fee;
            if (protocolFee > 0 && feeCollector != address(0)) {
                fee = protocolFee.mul(quoAmount).div(DENOMINATOR);
                quo.safeTransferToken(feeCollector, fee);
            }
            emit QuoHarvested(quoAmount, fee);
            quoAmount = quoAmount.sub(fee);
            _approveTokenIfNeeded(quo, address(rewardPool), quoAmount);
            rewardPool.queueNewRewards(quo, quoAmount);
        }
        _;
    }

    function setProtocolFee(uint256 _protocolFee) external onlyOwner {
        require(_protocolFee < DENOMINATOR, "invalid _protocolFee!");
        protocolFee = _protocolFee;
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "invalid _feeCollector!");
        feeCollector = _feeCollector;
    }

    function updateWeight(address _lp, uint256 _weight) external onlyManager {
        require(_lp != address(this), "??");
        if (!isVotePool[_lp]) {
            require(
                IBribeManager(bribeManager).isPoolActive(_lp),
                "Pool not active"
            );
            isVotePool[_lp] = true;
            votePools.push(_lp);
        }
        totalWeight = totalWeight.sub(votingWeights[_lp]).add(_weight);
        votingWeights[_lp] = _weight;
    }

    function deletePool(address _lp) external onlyOwner {
        require(isVotePool[_lp], "invalid _lp!");
        require(
            !IBribeManager(bribeManager).isPoolActive(_lp),
            "Pool still active"
        );

        isVotePool[_lp] = false;
        uint256 length = votePools.length;
        address[] memory newVotePool = new address[](length - 1);
        uint256 indexShift;
        for (uint256 i; i < length; i++) {
            if (votePools[i] == _lp) {
                indexShift = 1;
            } else {
                newVotePool[i - indexShift] = votePools[i];
            }
        }
        votePools = newVotePool;
        totalWeight = totalWeight - votingWeights[_lp];
        votingWeights[_lp] = 0;
        if (_getVoteForLp(_lp) > 0) {
            IBribeManager(bribeManager).unvote(_lp);
        }
        _updateVote();
    }

    function getPoolsLength() external view returns (uint256) {
        return votePools.length;
    }

    function getRewardTokens() public view returns (address[] memory) {
        return rewardPool.getRewardTokens();
    }

    function totalSupply() public view returns (uint256) {
        return rewardPool.totalSupply();
    }

    function balanceOf(address account) public view returns (uint256) {
        return rewardPool.balanceOf(account);
    }

    function earned(address _account, address _rewardToken)
        external
        view
        returns (uint256)
    {
        return rewardPool.earned(_account, _rewardToken);
    }

    function harvestManually() external harvest {
        return;
    }

    function stakeFor(address _for, uint256 _amount)
        external
        onlyBribeManager
        harvest
    {
        rewardPool.stakeFor(_for, _amount);
        _updateVote();
    }

    function withdrawFor(address _for, uint256 _amount)
        external
        onlyBribeManager
        harvest
    {
        rewardPool.withdrawFor(_for, _amount);
        _updateVote();
    }

    function getReward(address _for)
        external
        onlyBribeManager
        returns (
            address[] memory rewardTokensList,
            uint256[] memory earnedRewards
        )
    {
        rewardTokensList = getRewardTokens();
        uint256 length = rewardTokensList.length;
        earnedRewards = new uint256[](length);
        for (uint256 index = 0; index < length; ++index) {
            address rewardToken = rewardTokensList[index];
            earnedRewards[index] = rewardPool.earned(_for, rewardToken);
        }
        rewardPool.getReward(_for);
    }

    function _getVoteForLp(address _lp) internal view returns (uint256) {
        return
            IBribeManager(bribeManager).getUserVoteForPool(_lp, address(this));
    }

    function _updateVote() internal {
        uint256 length = votePools.length;
        int256[] memory deltas = new int256[](length);
        for (uint256 index = 0; index < length; ++index) {
            address pool = votePools[index];
            uint256 targetVote = votingWeights[pool].mul(totalSupply()).div(
                totalWeight
            );
            uint256 currentVote = _getVoteForLp(pool);
            deltas[index] = int256(targetVote) - int256(currentVote);
        }
        IBribeManager(bribeManager).vote(votePools, deltas);
    }

    function _approveTokenIfNeeded(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        if (IERC20(_token).allowance(address(this), _to) < _amount) {
            IERC20(_token).safeApprove(_to, 0);
            IERC20(_token).safeApprove(_to, type(uint256).max);
        }
    }

    receive() external payable {}
}

