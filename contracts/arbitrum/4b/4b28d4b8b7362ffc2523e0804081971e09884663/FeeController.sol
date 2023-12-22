// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC721.sol";
import "./ITimelock.sol";
import "./IVault.sol";
import "./IRewardTracker.sol";
import "./IRewardDistributor.sol";
import "./INftClubStaking.sol";
import "./ISolidlyRouter.sol";
import "./ISwapController.sol";


contract FeeController is Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct EpochReward {
        uint256 nextNftReward;
        uint256 nextStakeReward;
    }

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant ONE_WEEK = 7 * 24 * 3600;
    address public reward;
    address public vaultAddress;
    address public gov;
    address public nftClubStaking;

    address[] public swapTokens;
    mapping(address => bool) public isHandler;
    mapping(uint256 => EpochReward) public epochRewards;
    address public protocolAddress;
    address public externalRouterAddress;
    address public feeTokenTracker;
    address public feeLpTracker;
    uint256 public protocolWeight;
    uint256 public feeTokenWeight;
    uint256 public feeLpWeight;

    address public stakedTokenTracker;
    address public stakedLpTracker;
    uint256 public maxStakedTokenPerWeek;
    uint256 public maxStakedLpPerWeek;


    event Result(
        uint256 _protocolRewardAmount, uint256 _tokenRewardAmount, uint256 _lpRewardAmount, uint256 _nextNftClubReward
    );
    constructor() public {
    }

    modifier onlyGov() {
        require(msg.sender == gov, "FeeController: forbidden");
        _;
    }

    modifier checkAddress(address _address) {
        require(_address != address(0), "FeeController: Invalid address");
        _;
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }
    modifier onlyHandlerAndAbove() {
        require(msg.sender == gov || isHandler[msg.sender], "FeeController: forbidden");
        _;
    }

    function initialize(address _gov,
        address _reward, address _nftClubStaking,
        address _vaultAddress,
        address _protocolAddress,
        address _feeTokenTracker,
        address _feeLpTracker,
        address _externalRouterAddress,
        address _stakedTokenTracker,
        address _stakedLpTracker
    ) external initializer {
        gov = _gov;
        reward = _reward;
        protocolAddress = _protocolAddress;
        nftClubStaking = _nftClubStaking;
        feeTokenTracker = _feeTokenTracker;
        feeLpTracker = _feeLpTracker;
        vaultAddress = _vaultAddress;
        externalRouterAddress = _externalRouterAddress;
        protocolWeight = 1000;
        feeTokenWeight = 3000;
        feeLpWeight = 6000;
        stakedTokenTracker = _stakedTokenTracker;
        maxStakedTokenPerWeek = 30000e18;
        stakedLpTracker = _stakedLpTracker;
        maxStakedLpPerWeek = 20000e18;
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }


    function updateReward(
        address _reward
    ) external onlyGov checkAddress(_reward) {
        reward = _reward;
    }

    function updateFeeLpTracker(
        address _feeLpTracker
    ) external onlyGov checkAddress(_feeLpTracker) {
        feeLpTracker = _feeLpTracker;
    }

    function updateProtocolAddress(
        address _protocolAddress
    ) external onlyGov checkAddress(_protocolAddress) {
        protocolAddress = _protocolAddress;
    }

    function updateExternalRouterAddress(
        address _externalRouterAddress
    ) external onlyGov checkAddress(_externalRouterAddress) {
        externalRouterAddress = _externalRouterAddress;
    }

    function updateFeeTokenTracker(
        address _feeTokenTracker
    ) external onlyGov checkAddress(_feeTokenTracker) {
        feeTokenTracker = _feeTokenTracker;
    }


    function updateNftClubStaking(
        address _nftClubStaking
    ) external onlyGov checkAddress(_nftClubStaking) {
        nftClubStaking = _nftClubStaking;
    }


    function updateVaultAddress(
        address _vaultAddress
    ) external onlyGov checkAddress(_vaultAddress) {
        vaultAddress = _vaultAddress;
    }
    function updateStakedLpTracker(
        address _stakedLpTracker
    ) external onlyGov checkAddress(_stakedLpTracker) {
        stakedLpTracker = _stakedLpTracker;
    }
    function updateStakedTokenTracker(
        address _stakedTokenTracker
    ) external onlyGov checkAddress(_stakedTokenTracker) {
        stakedTokenTracker = _stakedTokenTracker;
    }

    function updateWeights(
        uint256 _protocolWeight,
        uint256 _feeTokenWeight,
        uint256 _feeLpWeight
    ) external onlyGov {
        require(_protocolWeight + _feeTokenWeight + _feeLpWeight == BASIS_POINTS_DIVISOR, "FeeController: Invalid weights");
        protocolWeight = _protocolWeight;
        feeTokenWeight = _feeTokenWeight;
        feeLpWeight = _feeLpWeight;
    }

    function updateMaxStakedPerWeek(
        uint256 _maxStakedTokenPerWeek,
        uint256 _maxStakedLpPerWeek
    ) external onlyGov {
        maxStakedTokenPerWeek = _maxStakedTokenPerWeek;
        maxStakedLpPerWeek = _maxStakedLpPerWeek;
    }


    function updateSwapTokens(
        address[] memory _swapTokens
    ) external onlyGov {
        swapTokens = _swapTokens;
    }

    function setStakedLpTokensPerWeek(uint256 _rewardPerWeek) public onlyHandlerAndAbove {
        require(_rewardPerWeek <= maxStakedLpPerWeek);
        setTokensPerWeek(stakedLpTracker, _rewardPerWeek);
    }

    function setStakedTokenTokensPerWeek(uint256 _rewardPerWeek) public onlyHandlerAndAbove {
        require(_rewardPerWeek <= maxStakedTokenPerWeek);
        setTokensPerWeek(stakedTokenTracker, _rewardPerWeek);
    }
    function setTokensPerWeek(address _trackerAddress, uint256 _rewardPerWeek) public onlyHandlerAndAbove {
        address _distributor = IRewardTracker(_trackerAddress).distributor();
        IRewardDistributor(_distributor).setTokensPerInterval(_rewardPerWeek / ONE_WEEK);
    }

    function transferAndSetTokensPerWeek(address _trackerAddress, uint256 _rewardPerWeek) internal {
        address _distributor = IRewardTracker(_trackerAddress).distributor();
        IERC20(reward).transfer(_distributor, _rewardPerWeek);
        IRewardDistributor(_distributor).setTokensPerInterval(_rewardPerWeek / ONE_WEEK);
    }

    function getPaymentAmount(uint256 _epochReward) public view returns (uint256 _protocolReward, uint256 _tokenReward, uint256 _lpReward) {
        _protocolReward = protocolWeight * _epochReward / BASIS_POINTS_DIVISOR;
        _tokenReward = feeTokenWeight * _epochReward / BASIS_POINTS_DIVISOR;
        _lpReward = feeLpWeight * _epochReward / BASIS_POINTS_DIVISOR;
    }

    function getCurrentEpochReward() public view returns (EpochReward memory _epochReward, uint256 _protocolReward, uint256 _tokenReward, uint256 _lpReward) {
        INftClubStaking _nftClubStaking = INftClubStaking(nftClubStaking);
        _epochReward = epochRewards[_nftClubStaking.epoch()];
        (_protocolReward, _tokenReward, _lpReward) = getPaymentAmount(_epochReward.nextStakeReward);


    }

    function trySwapAll() public onlyHandlerAndAbove {
        try this.swap(swapTokens){
        } catch {
            _swapAllUsingExternal(swapTokens);
        }
    }

    function _swap(address[] memory _swapTokens) internal {
        uint256 length = _swapTokens.length;
        IVault _vault = IVault(vaultAddress);
        for (uint256 i = 0; i < length; i++) {
            IERC20 token = IERC20(_swapTokens[i]);
            uint256 balance = token.balanceOf(address(this));
            if (balance > 0) {
                token.transfer(vaultAddress, balance);
                _vault.swap(_swapTokens[i], reward, address(this));
            }
        }
    }

    function _withdrawFees(address[] memory _swapTokens, address to) internal {
        ITimelock timelock = ITimelock(IVault(vaultAddress).gov());
        address admin = timelock.admin();
        uint256 length = _swapTokens.length;
        uint256[]  memory balances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            IERC20 token = IERC20(_swapTokens[i]);

            balances[i] = token.balanceOf(admin);

        }
        timelock.batchWithdrawFees(vaultAddress, _swapTokens);
        for (uint256 i = 0; i < length; i++) {
            IERC20 token = IERC20(_swapTokens[i]);
            uint256 diff = token.balanceOf(admin) - balances[i];
            if (diff > 0) {
                token.safeTransferFrom(admin, to, diff);
            }
        }
    }

    function withdrawFees(address[] memory _swapTokens) external onlyHandlerAndAbove {
        _withdrawFees(_swapTokens, address(this));
    }

    function swap(address[] memory _swapTokens) external onlyHandlerAndAbove {
        _swap(_swapTokens);
    }

    function swapAll() external onlyHandlerAndAbove {
        _swap(swapTokens);
    }


    function withDrawAll() external onlyHandlerAndAbove {
        _withDrawAll(address(this));
    }

    function withDrawAllToGov() external onlyGov {
        _withDrawAll(gov);
    }

    function swapAllUsingExternal(address[] memory _swapTokens) external onlyHandlerAndAbove {
        _swapAllUsingExternal(_swapTokens);
    }

    function _swapUsingExternal(address _token, uint256 _amount) internal {
        IERC20(_token).transfer(externalRouterAddress, _amount);
        ISwapController(externalRouterAddress).swap(_token, _amount, 1, address(this));
    }

    function _swapAllUsingExternal(address[] memory _swapTokens) internal {
        uint256 length = _swapTokens.length;
        for (uint256 i = 0; i < length; i++) {
            IERC20 token = IERC20(_swapTokens[i]);
            uint256 balance = token.balanceOf(address(this));
            if (balance > 0) {
                _swapUsingExternal(_swapTokens[i], balance);
            }
        }
    }

    function _withDrawAll(address to) internal {
        _withdrawFees(getAllToken(), to);
    }

    function withDrawnAndSwap() public onlyHandlerAndAbove {
        _withDrawAll(address(this));
        trySwapAll();
    }

    function setNextEpochReward(uint256 poolReward, uint256 nftReward) public onlyHandlerAndAbove {
        uint256 totalReward = poolReward + nftReward;
        IERC20 _reward = IERC20(reward);
        uint256 currentRewardBalance = _reward.balanceOf(address(this));
        if (currentRewardBalance < totalReward) {
            _reward.transferFrom(msg.sender, address(this), totalReward - currentRewardBalance);
        }
        INftClubStaking _nftClubStaking = INftClubStaking(nftClubStaking);
        epochRewards[_nftClubStaking.epoch()] = EpochReward(nftReward, poolReward);
    }

    function run() public onlyHandlerAndAbove {
        IERC20 _reward = IERC20(reward);
        INftClubStaking _nftClubStaking = INftClubStaking(nftClubStaking);
        EpochReward memory _epochReward = epochRewards[_nftClubStaking.epoch()];
        require(_epochReward.nextNftReward > 0 && _epochReward.nextStakeReward > 0, "Invalid epoch reward");
        (uint256 _protocolRewardAmount, uint256 _tokenRewardAmount, uint256 _lpRewardAmount) = getPaymentAmount(_epochReward.nextStakeReward);
        require(_protocolRewardAmount > 0 && _tokenRewardAmount > 0 && _lpRewardAmount > 0, "Invalid reward amount");
        _reward.transfer(protocolAddress, _protocolRewardAmount);
        transferAndSetTokensPerWeek(feeLpTracker, _lpRewardAmount);
        transferAndSetTokensPerWeek(feeTokenTracker, _tokenRewardAmount);
        _nftClubStaking.allocateReward();
        _reward.transfer(_nftClubStaking.distributor(), _epochReward.nextNftReward);
        _nftClubStaking.setEpochReward(_epochReward.nextNftReward);
        emit Result(_protocolRewardAmount, _tokenRewardAmount, _lpRewardAmount, _epochReward.nextNftReward);
    }

    function getAllToken() public view returns (address[] memory) {
        uint256 length = swapTokens.length;
        address[]  memory _swapTokens = new address[](length + 1);
        for (uint256 i = 0; i < length; i++) {
            _swapTokens[i] = swapTokens[i];
        }
        _swapTokens[length] = (reward);
        return _swapTokens;
    }

    function transferAll() external onlyGov {
        address[]  memory allTokens = getAllToken();
        for (uint256 i = 0; i < allTokens.length; i++) {
            IERC20 _token = IERC20(allTokens[i]);
            _token.transfer(gov, _token.balanceOf(address(this)));
        }
    }

    function governanceRecoverUnsupported(IERC20 _token) external onlyGov {
        _token.transfer(gov, _token.balanceOf(address(this)));
    }
}

