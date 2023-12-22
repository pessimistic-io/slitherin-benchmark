// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { ERC20PermitUpgradeable } from "./draft-ERC20PermitUpgradeable.sol";
import { ERC20VotesUpgradeable } from "./ERC20VotesUpgradeable.sol";

import { IVoteLockArchi } from "./IVoteLockArchi.sol";
import { ITokenRelease } from "./ITokenRelease.sol";

contract VoteLockArchi is
    Initializable,
    ReentrancyGuardUpgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    IVoteLockArchi,
    OwnableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    address public override wrappedToken;
    address public tokenRelease;
    address public distributor;
    uint256 public override totalRewardTokens;

    mapping(uint256 => RewardToken) private _rewardTokens;
    mapping(address => uint256) private _rewardTokenToIndex;

    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) public userRewards;

    event Stake(address _recipient, uint256 _amountIn, address _delegatee);
    event Redeem(address _recipient, uint256 _amountOut);
    event AddRewardToken(uint256 _totalRewardTokens, address _rewardToken);
    event Claim(address _recipient, address _rewardToken, uint256 _rewards);
    event Distribute(address _rewardToken, uint256 _rewards, uint256 _accRewardPerShare);

    modifier onlyDistributor() {
        require(distributor == msg.sender, "VoteLockArchi: Caller is not distributor");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(address _wrappedToken, address _tokenRelease, address _distributor) external initializer {
        __ERC20_init("Vote-lock Archi", "vlARCHI");
        __ERC20Permit_init("Vote-lock Archi");
        __ReentrancyGuard_init();
        __Ownable_init();

        wrappedToken = _wrappedToken;
        tokenRelease = _tokenRelease;
        distributor = _distributor;
    }

    function getRewardToken(uint256 _index) external view override returns (address) {
        return _rewardTokens[_index].token;
    }

    function stake(uint256 _amountIn, address _delegatee) external override nonReentrant {
        require(_amountIn > 0, "VoteLockArchi: _amountIn cannot be 0");

        _updateReward(msg.sender);

        {
            uint256 before = IERC20Upgradeable(wrappedToken).balanceOf(address(this));
            IERC20Upgradeable(wrappedToken).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(wrappedToken).balanceOf(address(this)) - before;
        }

        _mint(msg.sender, _amountIn);
        _delegate(msg.sender, _delegatee);

        emit Stake(msg.sender, _amountIn, _delegatee);
    }

    function redeem(uint256 _amountOut) external nonReentrant {
        require(_amountOut > 0, "VoteLockArchi: _amountOut cannot be 0");

        _updateReward(msg.sender);
        _burn(msg.sender, _amountOut);

        IERC20Upgradeable(wrappedToken).safeApprove(address(tokenRelease), 0);
        IERC20Upgradeable(wrappedToken).safeApprove(address(tokenRelease), _amountOut);

        ITokenRelease(tokenRelease).addFund(msg.sender, _amountOut);

        emit Redeem(msg.sender, _amountOut);
    }

    function addRewardToken(address _rewardToken) public onlyOwner {
        require(_rewardTokenToIndex[_rewardToken] == 0, "VoteLockArchi: Duplicate _rewardToken");

        totalRewardTokens++;
        _rewardTokenToIndex[_rewardToken] = totalRewardTokens;
        _rewardTokens[totalRewardTokens] = RewardToken({ token: _rewardToken, accRewardPerShare: 0, queuedRewards: 0 });

        emit AddRewardToken(totalRewardTokens, _rewardToken);
    }

    function setDistributor(address _distributor) public onlyOwner {
        require(_distributor != address(0), "VoteLockArchi: _distributor cannot be 0x0");

        distributor = _distributor;
    }

    function pendingRewards(address _recipient) public view override returns (uint256[] memory) {
        uint256[] memory rewards = new uint256[](totalRewardTokens);

        for (uint256 i = 0; i < totalRewardTokens; i++) {
            RewardToken storage rewardToken = _rewardTokens[i + 1];

            rewards[i] =
                userRewards[_recipient][rewardToken.token] +
                ((rewardToken.accRewardPerShare - userRewardPerTokenPaid[_recipient][rewardToken.token]) * balanceOf(_recipient)) /
                1e18;
        }

        return rewards;
    }

    function claim() external override nonReentrant returns (uint256[] memory) {
        _updateReward(msg.sender);

        uint256[] memory rewards = new uint256[](totalRewardTokens);

        for (uint256 i = 0; i < totalRewardTokens; i++) {
            RewardToken storage rewardToken = _rewardTokens[i + 1];

            rewards[i] = userRewards[msg.sender][rewardToken.token];

            if (rewards[i] > 0) {
                userRewards[msg.sender][rewardToken.token] = 0;
                IERC20Upgradeable(rewardToken.token).safeTransfer(msg.sender, rewards[i]);

                emit Claim(msg.sender, rewardToken.token, rewards[i]);
            }
        }

        return rewards;
    }

    function isRewardToken(address _rewardToken) external view returns (bool) {
        uint256 index = _rewardTokenToIndex[_rewardToken];

        return index > 0 ? true : false;
    }

    function _updateReward(address _recipient) internal {
        uint256[] memory rewards = pendingRewards(_recipient);
        for (uint256 i = 0; i < totalRewardTokens; i++) {
            RewardToken storage rewardToken = _rewardTokens[i + 1];
            userRewards[_recipient][rewardToken.token] = rewards[i];
            userRewardPerTokenPaid[_recipient][rewardToken.token] = rewardToken.accRewardPerShare;
        }
    }

    function distribute(address _rewardToken, uint256 _rewards) external nonReentrant onlyDistributor {
        require(_rewardTokenToIndex[_rewardToken] > 0, "VoteLockArchi: _rewardToken empty");
        require(_rewards > 0, "VoteLockArchi: _rewards cannot be 0");

        IERC20Upgradeable(_rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);

        uint256 index = _rewardTokenToIndex[_rewardToken];
        RewardToken storage rewardToken = _rewardTokens[index];

        if (totalSupply() == 0) {
            rewardToken.queuedRewards = rewardToken.queuedRewards + _rewards;
        } else {
            _rewards = _rewards + rewardToken.queuedRewards;
            rewardToken.accRewardPerShare = rewardToken.accRewardPerShare + (_rewards * 1e18) / totalSupply();
            rewardToken.queuedRewards = 0;

            emit Distribute(_rewardToken, _rewards, rewardToken.accRewardPerShare);
        }
    }

    // The functions below are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        if (from == address(0) || to == address(0)) {
            return super._afterTokenTransfer(from, to, amount);
        }

        revert("VoteLockArchi: vlARCHI does not allow transfer");
    }

    function _mint(address to, uint256 amount) internal override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._burn(account, amount);
    }
}

