/*
 * SPDX-License-Identifier: UNLICENSED
 * Copyright © 2022 Blocksquare d.o.o.
 */

pragma solidity 0.8.14;

import "./IERC20.sol";
import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuard.sol";

/// @notice A collection of helper functions
interface BSPTStakingHelpers {
    function mint(address to, uint256 amount) external;

    function owner() external view returns (address);

    function getPropertyValuation(address property)
        external
        view
        returns (uint256);

    function getCPOfProperty(address prop) external view returns (address);

    function sellBSPT(
        address property,
        address user,
        uint256 stakedBSPT
    ) external returns (bool);

    function addVestingInfo(
        address property,
        address user,
        uint256 amount
    ) external returns (bool);
}

/// @title Blocksquare Property Token Staking
/// @author David Šenica
/// @notice Allows to stake different BSPT
contract BSPTStaking is OwnableUpgradeable, ERC20Upgradeable, ReentrancyGuard {
    string private constant _NAME = "sBlocksquarePropertyToken";
    string private constant _SYMBOL = "sBSPT";
    uint256 private constant _EIGHTEEN_DECIMALS = 10**18;
    uint256 private constant _BSPT_TOTAL_SUPPLY = _EIGHTEEN_DECIMALS * 100_000;

    uint256 private _lockPeriod;
    uint256 private _fee;
    uint256 private _tbsptBalanceThis;
    uint256 private _totalValuation;
    address private _oceanPoint;
    address private _propertyRegistry;
    address private _dataProxy;
    address private _rewardVesting;

    IERC20 private _rewardToken;

    mapping(address => mapping(address => uint256)) private _lockedUntil;
    mapping(address => mapping(address => uint256)) private _bsptStaked;
    mapping(address => mapping(address => uint256)) private _tBSPT;
    mapping(address => mapping(address => uint256)) private _sBSPT;

    /// @notice Event triggers every time a deposit is made
    /// @param owner Address of user wallet
    /// @param property BSPT address
    /// @param inAmount Amount of BSPT staked
    /// @param outAmount Amount of staked BSPT returned (your share in the pool)
    /// @param lockedUntil Timestamp when withdrawal can be made
    event Deposit(
        address indexed owner,
        address property,
        uint256 inAmount,
        uint256 outAmount,
        uint256 lockedUntil
    );
    /// @notice Event triggers every time a withdrawal is made
    /// @param owner Address of user wallet
    /// @param property BSPT address
    /// @param inAmount Amount of staked BSPT
    /// @param outAmount Amount of BSPT returned
    /// @param rewardToUser Amount of BST user got as reward
    /// @param rewardToFeeReciever Amount of BST received by certified partner as fee
    /// @param isWithdraw Whether user withdrew BSPT or sold them to oceanpoint contract
    event Withdraw(
        address indexed owner,
        address property,
        uint256 inAmount,
        uint256 outAmount,
        uint256 rewardToUser,
        uint256 rewardToFeeReciever,
        bool isWithdraw
    );
    /// @notice Event triggers every time a reward is added
    /// @param from Address of user who added reward
    /// @param amount Amount of BST added as reward
    event Reward(address indexed from, uint256 amount);

    /// @dev Initialize contract params with `initialize` function behind a proxy
    constructor() initializer {
        // Only interact with this contract through proxy
    }

    /// @notice Initialize contract. Can only be called once
    /// @param rewardToken Address of reward token (BST token)
    /// @param propertyRegistry Address of smart contract where properties that can be staked are stored
    /// @param dataProxy Address of smart contract where information about certified partner is held
    /// @param owner Address of owner of this contract
    function initialize(
        address rewardToken,
        address propertyRegistry,
        address dataProxy,
        address owner
    ) external initializer {
        require(
            rewardToken != address(0) &&
                propertyRegistry != address(0) &&
                dataProxy != address(0) &&
                owner != address(0),
            "BSPTStaking: Address iz zero"
        );
        _rewardToken = IERC20(rewardToken);
        _transferOwnership(owner);
        __ERC20_init(_NAME, _SYMBOL);
        changePropertyRegistry(propertyRegistry);
        changeDataProxy(dataProxy);
        changeLockPeriod(60 * 60 * 24 * 30 * 6);
        changeRewardFee(1000);
        // 10 %
    }

    /// @notice Calculates sBSPT based on different BSPT already in contract and reward
    /// @dev Each BSPT has different weight based on its evaluation,
    ///      meaning different BSPT (when depositing same amount of BSPT) will yield different amount of sBSPT
    ///      Each BSPT is fixed at 100000 supply
    /// @param property Address of property token
    /// @param user Address of user, making deposit
    /// @param amount Amount of property tokens being deposited
    /// @param propertyValuation Evaluation of property
    /// @return amountsbsptToMint Amount of sBSPT depositor should receive
    function _updateBeforeStakeStart(
        address property,
        address user,
        uint256 amount,
        uint256 propertyValuation
    ) private returns (uint256 amountsbsptToMint) {
        _lockedUntil[property][user] = block.timestamp + _lockPeriod;
        uint256 tempBSPTAmount = (amount * propertyValuation) /
            _BSPT_TOTAL_SUPPLY;
        uint256 tempBSPTBalance = _tbsptBalanceThis;
        uint256 sbsptSupply = totalSupply();
        amountsbsptToMint = (sbsptSupply == 0 || tempBSPTBalance == 0)
            ? tempBSPTAmount
            : (tempBSPTAmount * sbsptSupply) / tempBSPTBalance;
        _bsptStaked[property][user] += amount;
        _tbsptBalanceThis += tempBSPTAmount;
        _totalValuation += tempBSPTAmount;
        _tBSPT[property][user] += tempBSPTAmount;
        _sBSPT[property][user] += amountsbsptToMint;
        emit Deposit(
            user,
            property,
            amount,
            amountsbsptToMint,
            _lockedUntil[property][user]
        );
    }

    /// @notice Calculates reward and BSPT user should get
    /// @param property Address of property
    /// @param user Address of user
    /// @return reward Amount of reward
    /// @return share Amount of sBSPT user should get
    function _updateAtStakeEnd(address property, address user)
        private
        returns (uint256 reward, uint256 share)
    {
        uint256 tempBSPTBalance = _tbsptBalanceThis;
        uint256 sbsptSupply = totalSupply();
        share = _sBSPT[property][user];
        _sBSPT[property][user] = 0;
        uint256 tempBSPTToReturn = ((share * tempBSPTBalance * 1000) /
            (sbsptSupply * 100000)) * 100;
        // This fixes some small rounding errors
        _burn(user, share);
        if(tempBSPTToReturn > _tBSPT[property][user]) {
            reward = tempBSPTToReturn - _tBSPT[property][user];
        } else {
            reward = 0;
        }
        _tBSPT[property][user] = 0;
        _tbsptBalanceThis -= tempBSPTToReturn;
        _totalValuation -= (tempBSPTToReturn - reward);
    }

    /// @notice Deposit BSPT for staking
    /// @dev Only one combination wallet-property can be staked, this means that
    ///      stake amount cannot increase for that combination and withdrawal needs to be done before depositing again
    ///      There is a fee on transferring BSPT so the `amount` deposited is bigger then the staking amount
    /// @param property Address of property
    /// @param amount Amount of BSPT to stake
    function deposit(address property, uint256 amount) external nonReentrant {
        require(
            _bsptStaked[property][_msgSender()] == 0,
            "BSPTStaking: You need to transfer staked BSPT"
        );
        // This should ensure only BSPT in our system can be used for staking
        uint256 propertyValuation = BSPTStakingHelpers(_propertyRegistry)
            .getPropertyValuation(property);
        require(
            propertyValuation > 0 && propertyValuation / _EIGHTEEN_DECIMALS > 0,
            "BSPTStaking: Invalid valuation"
        );
        // If normal user transfers then the 1.5% fee on BSPT applies
        // meaning less then amount of BSPT comes into this contract
        uint256 balanceBeforeTransfer = IERC20(property).balanceOf(
            address(this)
        );
        require(
            IERC20(property).transferFrom(_msgSender(), address(this), amount),
            "BSPTStaking: Couldn't transfer BSPT"
        );
        uint256 balanceAfterTransfer = IERC20(property).balanceOf(
            address(this)
        );
        uint256 amountToMint = _updateBeforeStakeStart(
            property,
            _msgSender(),
            balanceAfterTransfer - balanceBeforeTransfer,
            propertyValuation
        );
        _mint(_msgSender(), amountToMint);
    }

    /// @notice Called when withdrawing BSPT or selling them to oceanpoint
    /// @dev Handles withdraw and selling to oceanpoint in one function
    /// @param property Address of property
    /// @param user Address user
    /// @param isWithdraw True if user is withdrawing and false if user is selling to oceanpoint
    /// @return stakedBSPT Amount of staked BSPT that should be returned or sold
    function _withdraw(
        address property,
        address user,
        bool isWithdraw
    ) private returns (uint256 stakedBSPT) {
        require(
            _lockedUntil[property][_msgSender()] < block.timestamp,
            "BSPTStaking: You need to wait for time lock to expire."
        );
        require(
            _sBSPT[property][user] > 0,
            "BSPTStaking: You need to stake BSPT for this property."
        );
        (uint256 reward, uint256 share) = _updateAtStakeEnd(
            property,
            _msgSender()
        );
        uint256 feeReward = (reward * _fee) / 10000;
        reward -= feeReward;
        if (_rewardVesting != address(0)) {
            require(
                _rewardToken.approve(_rewardVesting, reward),
                "BSPTStaking: Couldn't approve for vesting"
            );
            require(
                BSPTStakingHelpers(_rewardVesting).addVestingInfo(
                    property,
                    user,
                    reward
                ),
                "BSPTStaking: Couldn't add vesting"
            );
        } else {
            require(
                _rewardToken.transfer(user, reward),
                "BSPTStaking: Couldn't transfer reward"
            );
        }
        require(
            _rewardToken.transfer(
                BSPTStakingHelpers(_dataProxy).getCPOfProperty(property),
                feeReward
            ),
            "BSPTStaking: Couldn't transfer fee reward"
        );
        stakedBSPT = _bsptStaked[property][_msgSender()];
        _bsptStaked[property][_msgSender()] = 0;
        emit Withdraw(
            _msgSender(),
            property,
            share,
            stakedBSPT,
            reward,
            feeReward,
            isWithdraw
        );
    }

    /// @notice It withdraws all BSPT for given property
    /// @param property Address of property
    function withdraw(address property) external nonReentrant {
        uint256 stakedBSPT = _withdraw(property, _msgSender(), true);
        require(
            IERC20(property).transfer(_msgSender(), stakedBSPT),
            "BSPTStaking: Couldn't transfer BSPT on withdrawal"
        );
    }

    /// @notice It sells all BSPT for given property to oceanpoint contract
    /// @param property Address of property
    function sellBSPTToOceanPoint(address property) external nonReentrant {
        uint256 stakedBSPT = _withdraw(property, _msgSender(), false);
        address user = _msgSender();
        require(
            IERC20(property).approve(_oceanPoint, stakedBSPT),
            "BSPTStaking: Couldn't approve oceanpoint"
        );
        require(
            BSPTStakingHelpers(_oceanPoint).sellBSPT(
                property,
                user,
                stakedBSPT
            ),
            "BSPTStaking: Couldn't sell to oceanpoint"
        );
    }

    /// @notice Adds `amount` reward
    /// @param amount Amount of reward
    function addReward(uint256 amount) external nonReentrant {
        require(
            _rewardToken.transferFrom(_msgSender(), address(this), amount),
            "BSPTStaking: Couldn't add reward"
        );
        _tbsptBalanceThis += amount;
        emit Reward(_msgSender(), amount);
    }

    // @dev Don't allow the transfer of sBSPT (sBPST token is only used for tracking share)
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        revert("sBSPT is non transferable");
    }

    /// @notice Change the duration before user can withdraw deposited tokens
    /// @param newPeriod Duration in seconds
    function changeLockPeriod(uint256 newPeriod) public onlyOwner {
        _lockPeriod = newPeriod;
    }

    /// @notice Change percentage of reward that goes to certified partner.
    /// @param newFee New percent, it need additional two zeros (for 10 percent value should be 1000)
    function changeRewardFee(uint256 newFee) public onlyOwner {
        _fee = newFee;
    }

    /// @notice Change oceanpoint contract address
    /// @param newOceanPoint New oceanpoint contract address
    function changeOceanPointContract(address newOceanPoint)
        external
        onlyOwner
    {
        _oceanPoint = newOceanPoint;
    }

    /// @notice Change address of data proxy contract
    /// @param newDataProxy Address of new data proxy
    function changeDataProxy(address newDataProxy) public onlyOwner {
        _dataProxy = newDataProxy;
    }

    /// @notice Change address of property registry contract
    /// @param newPropertyRegistry address of new property registry
    function changePropertyRegistry(address newPropertyRegistry)
        public
        onlyOwner
    {
        _propertyRegistry = newPropertyRegistry;
    }

    /// @notice Change vesting contract address
    /// @param newVestingReward New vesting contract address
    function changeVestingRewardContract(address newVestingReward)
        external
        onlyOwner
    {
        _rewardVesting = newVestingReward;
    }

    /// @notice Get current fee
    /// @return Fee amount
    function getRewardFee() external view returns (uint256) {
        return _fee;
    }

    /// @notice Get current lock duration
    /// @return Duration in seconds
    function getLockPeriod() external view returns (uint256) {
        return _lockPeriod;
    }

    /// @notice Get amount of BSPT staked for `user`
    /// @param property Address of property
    /// @param user Address of user wallet
    /// @return Amount of BSPT staked
    function getBSPTStaked(address property, address user)
        external
        view
        returns (uint256)
    {
        return _bsptStaked[property][user];
    }

    /// @notice Get amount of sBSPT for `property` `user` combination
    /// @param property Address of property
    /// @param user Address of user wallet
    /// @return Amount of sBSPT
    function getsBSPTWalletProperty(address property, address user)
        external
        view
        returns (uint256)
    {
        return _sBSPT[property][user];
    }

    /// @notice Get oceanpoint contract address
    /// @return Oceanpoint address
    function getOceanPointContract() external view returns (address) {
        return _oceanPoint;
    }

    /// @notice Get vesting contract address
    /// @return Vesting address
    function getVestingRewardContract() external view returns (address) {
        return _rewardVesting;
    }

    /// @notice Get total evaluation of BSPTs in this contract
    /// @return Total evaluation
    function getTotalValuation() external view returns (uint256) {
        return _totalValuation;
    }

    /// @notice Get reward for wallet and given property
    /// @param wallet Address of user wallet
    /// @param property Address of property
    /// @param withoutFee If we should return reward without the fee subtraction
    /// @return reward Amount of reward wallet will receive for given property
    function getUnclaimedReward(
        address wallet,
        address property,
        bool withoutFee
    ) external view returns (uint256 reward) {
        uint256 tempBSPTToReturn = ((_sBSPT[property][wallet] *
            _tbsptBalanceThis *
            1000) / (totalSupply() * 100000)) * 100;
        if(tempBSPTToReturn > _tBSPT[property][wallet]) {
            reward = tempBSPTToReturn - _tBSPT[property][wallet];
        } else {
            reward = 0;
        }
        if (withoutFee) {
            uint256 feeReward = (reward * _fee) / 10000;
            reward -= feeReward;
        }
    }
}

